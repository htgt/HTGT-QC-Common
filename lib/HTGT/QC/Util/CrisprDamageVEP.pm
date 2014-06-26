package HTGT::QC::Util::CrisprDamageVEP;
## no critic(RequireUseStrict,RequireUseWarnings)
{
    $HTGT::QC::Util::CrisprDamageVEP::VERSION = '0.020';
}
## use critic


=head1 NAME

HTGT::QC::Util::CrisprDamageVEP

=head1 DESCRIPTION

Identify damage caused by crispr pairs on the second allele.
Compare wildtype genomic sequence of area around crispr pair target site with the sequence
from primer reads that flank this target site.
Try to predict the effect of the damage using Ensemble's Varient Effect Predictor (VEP) software.

=cut

use Moose;
use HTGT::QC::Util::DrawPileupAlignment;
use Bio::SeqIO;
use MooseX::Types::Path::Class::MoreCoercions qw/AbsDir/;
use IPC::Run 'run';
use Const::Fast;
use namespace::autoclean;

with qw( MooseX::Log::Log4perl );

const my $BWA_MEM_CMD  => $ENV{BWA_MEM_CMD}
    // '/software/vertres/bin-external/bwa-0.7.5a-r406/bwa';
const my $SAMTOOLS_CMD => $ENV{SAMTOOLS_CMD}
    // '/software/vertres/bin-external/samtools-0.2.0-rc8/bin/samtools';
const my $BCFTOOLS_CMD => $ENV{BCFTOOLS_CMD}
    // '/software/vertres/bin-external/samtools-0.2.0-rc8/bin/bcftools';
const my $VEP_CMD => $ENV{VEP_CMD}
    // '/opt/t87/global/software/ensembl-tools-release-75/scripts/variant_effect_predictor/variant_effect_predictor.pl';
const my $VEP_CACHE_DIR => $ENV{VEP_CACHE_DIR}
    // '/lustre/scratch109/blastdb/Ensembl/vep';

const my %BWA_REF_GENOMES => (
    human => '/lustre/scratch109/blastdb/Users/team87/Human/bwa/Homo_sapiens.GRCh37.toplevel.clean_chr_names.fa',
    mouse => '/lustre/scratch109/blastdb/Users/team87/Mouse/bwa/Mus_musculus.GRCm38.toplevel.clean_chr_names.fa',
);

has species => (
    is       => 'ro',
    isa      => 'Str',
    required => 1,
);

has [ 'target_start', 'target_end' ] => (
    is       => 'ro',
    isa      => 'Int',
    required => 1,
);

has target_chr => (
    is       => 'ro',
    isa      => 'Str',
    required => 1,
);

has target_region_padding => (
    is      => 'ro',
    isa     => 'Int',
    default => 10,
);

has forward_primer_read => (
    is        => 'ro',
    isa       => 'Maybe[Bio::Seq]',
    predicate => 'has_forward_primer_read',
    trigger   => \&_clean_read_seq,
);

has reverse_primer_read => (
    is        => 'ro',
    isa       => 'Maybe[Bio::Seq]',
    predicate => 'has_reverse_primer_read',
    trigger   => \&_clean_read_seq,
);

# replace dashes with N characters in read sequence so bwa mem will work
sub _clean_read_seq {
    my ( $self, $bio_seq ) = @_;

    ( my $cleaned_seq = $bio_seq->seq ) =~ s/-/N/g;
    $bio_seq->seq( $cleaned_seq );

    return;
}

has sam_file => (
    is        => 'rw',
    isa       => 'Path::Class::File',
    predicate => 'has_sam_file',
    coerce    => 1,
);

has [
    'bam_file', 'filtered_bam_file', 'bcf_file',      'pileup_file',
    'vcf_file', 'vep_file',          'vep_html_file', 'vcf_file_target_region',
    'ref_aa_file', 'mut_aa_file',
    ] => (
    is  => 'rw',
    isa => 'Path::Class::File',
);

has num_target_region_alignments => (
    is      => 'rw',
    isa     => 'Num',
    default => 0,
);

has pileup_parser => (
    is  => 'rw',
    isa => 'HTGT::QC::Util::DrawPileupAlignment',
);

has dir => (
    is       => 'ro',
    isa      => AbsDir,
    required => 1,
    coerce   => 1,
);

=read2 BUILD

Hopefully can send provide a SAM alignment file for the reads we are interested in,
this should mean we run bwa mem once and split up the SAM file to send into this module.
Otherwise we need to run bwa mem to generate the SAM file.

=cut
sub BUILD {
    my $self = shift;

    if ( !$self->has_sam_file ) {
        $self->align_reads;
    }

    return;
}

=head2 analyse

Run the analysis

=cut
sub analyse {
    my ( $self ) = @_;

    $self->sam_to_bam;
    $self->remove_reads_not_overlapping_target;
    $self->run_mpileup;
    $self->parse_pileup_file;
    $self->variant_calling;
    $self->target_region_vcf_file;
    $self->variant_effect_predictor;

    return;
}

=head2 sam_to_bam

Convert sam file to a sorted bam file, ready for input
into mpileup. Also filter out secondary alignments.

The log file may contain a warning about EOF marker is absent,
this is a known bug and the warning can be ignored.

=cut
sub sam_to_bam {
    my ( $self ) = @_;
    $self->log->info('Converting SAM file to sorted BAM file');

    my @samtools_sort_command = (
        $SAMTOOLS_CMD,
        'sort',                     # sort command
        '-o',                       # output to STDOUT
        $self->sam_file->stringify, # alignment file
        'deleteme',                 # samtools sort always needs a output prefix
    );

    my @samtools_view_command = (
        $SAMTOOLS_CMD,
        'view',                     # align command
        '-b',                       # output is compressed BAM file
        '-',                        # input from pipe
        '-F', 2048,                 # filter alignments with bit present in secondary alignment
    );

    $self->log->debug( "samtools sort command: " . join( ' ', @samtools_sort_command ) );
    $self->log->debug( "samtools view command: " . join( ' ', @samtools_view_command ) );

    my $bam_file = $self->dir->file('alignment.bam')->absolute;
    my $log_file = $self->dir->file( 'sam_to_bam.log' )->absolute;
    run( \@samtools_sort_command,
        '|',
        \@samtools_view_command,
        '>',  $bam_file->stringify,
        '2>', $log_file->stringify
    ) or die (
            "Failed to run bwa sam to bam commands, see log file: $log_file" );

    $self->bam_file( $bam_file );
    return;
}

=head2 remove_reads_not_overlapping_target

Index the bam file then filter out alignments that do not hit the target region.
We use samtools view with the target region specified to do this.

=cut
sub remove_reads_not_overlapping_target {
    my ( $self ) = @_;
    $self->log->info('Filter reads that do not overlap target region');

    my @samtools_index_command = (
        $SAMTOOLS_CMD,
        'index',                    # index command
        $self->bam_file->stringify, # bam file to index
    );
    $self->log->debug( "samtools index command: " . join( ' ', @samtools_index_command ) );

    my $log_file = $self->dir->file( 'check_overlap.log' )->absolute;
    run( \@samtools_index_command,
        '2>', $log_file->stringify
    ) or die (
            "Failed to run samtools index, see log file: $log_file" );

    my $target_string = $self->target_chr . ":"
        . ( $self->target_start - 100 ) . "-"
        . ( $self->target_end + 100 );
    # first check we have at least one read overlapping target region
    my @check_command = (
        $SAMTOOLS_CMD,
        'view',                     # view command
        '-c',                       # output is compressed BAM file
        $self->bam_file->stringify, # bam file
        $target_string,             # string specifying target region for crispr
    );
    $self->log->debug( "samtools view count overlapping reads command: " . join( ' ', @check_command ) );

    my $out;
    run( \@check_command,
        '>', \$out,
        '2>', $log_file->stringify
    ) or die (
            "Failed to run samtools view, see log file: $log_file" );

    chomp( $out );
    die( "We don't have any reads that overlap the target region" ) unless $out;
    $self->log->info("We have $out reads that overlap the target region");
    $self->num_target_region_alignments($out);

    # now do the actual filtering
    my @filter_command = (
        $SAMTOOLS_CMD,
        'view',                     # view command
        '-b',                       # output is compressed BAM file
        $self->bam_file->stringify, # bam file
        $target_string,             # string specifying target region for crispr
    );
    $self->log->debug( "samtools view filter command: " . join( ' ', @filter_command ) );

    $self->filtered_bam_file( $self->dir->file('alignment_filtered.bam')->absolute );
    run( \@filter_command,
        '>', $self->filtered_bam_file->stringify,
        '2>', $log_file->stringify
    ) or die (
            "Failed to run samtools view, see log file: $log_file" );

    return;
}

=head2 run_mpileup

Run mpileup, input is bam file.
We want pileup and bcf output.

    # run mpileup on the sorted bam file ( we want both the pileup and bcf format out here )
        # can convert pileup to vcf / vice versa
        # do we want vcf or pileup from mpileup?

=cut
sub run_mpileup {
    my ( $self  ) = @_;
    $self->log->info('Running mpileup command to generate bcf file');

    my $output_bcf_file = $self->dir->file('raw_analysis.bcf')->absolute;
    my $output_pileup_file = $self->dir->file('analysis.pileup')->absolute;
    my $log_file = $self->dir->file( 'mpileup.log' )->absolute;

    my @mpileup_command = (
        $SAMTOOLS_CMD,
        'mpileup',                                      # mpileup command
        '-Q', 0,                                        # minimum base quality
        '-f', $BWA_REF_GENOMES{ lc( $self->species ) }, # reference genome file, faidx-indexed
        $self->filtered_bam_file->stringify,
    );

    $self->log->debug( "mpileup command: " . join( ' ', @mpileup_command ) );
    run( \@mpileup_command,
        '>', $output_pileup_file->stringify,
        '2>', $log_file->stringify
    ) or die(
            "Failed to run mpileup command, see log file: $log_file" );
    $self->pileup_file( $output_pileup_file );

    my @mpileup_bcf_command = (
        $SAMTOOLS_CMD,
        'mpileup',                                      # mpileup command
        '-g',                                           # output is compressed BCF file
        '-Q', 0,                                        # minimum base quality
        '-f', $BWA_REF_GENOMES{ lc( $self->species ) }, # reference genome file, faidx-indexed
        $self->filtered_bam_file->stringify,
    );

    $self->log->debug( "mpileup bcf command: " . join( ' ', @mpileup_bcf_command ) );
    run( \@mpileup_bcf_command,
        '>', $output_bcf_file->stringify,
        '2>', $log_file->stringify
    ) or die(
            "Failed to run mpileup command, see log file: $log_file" );

    $self->bcf_file( $output_bcf_file );
    return;
}

=head2 parse_pileup_file

Parse the pileup file, generate following information:
* Read alignment strings to show to user.
* Genome start and end coordinates for reference sequence string.
* Hash of insertion sequences keyed on insert position ( relative to ref string, not genome ).

=cut
sub parse_pileup_file {
    my ( $self ) = @_;

    my $pileup_parser = HTGT::QC::Util::DrawPileupAlignment->new(
        pileup_file  => $self->pileup_file,
        target_start => $self->target_start,
        target_end   => $self->target_end,
        target_chr   => $self->target_chr,
        dir          => $self->dir,
        species      => $self->species,
    );

    $pileup_parser->calculate_pileup_alignment;
    $self->pileup_parser( $pileup_parser );
    return;
}

=head2 variant_calling

Use bcftools call to find the SNP/Indels

=cut
sub variant_calling {
    my ( $self ) = @_;
    $self->log->info( 'Calling variants with bcftools call' );

    my $output_vcf_file = $self->dir->file('analysis.vcf')->absolute;
    my $log_file = $self->dir->file( 'bcftools_call.log' )->absolute;
    my @bcftools_command = (
        $BCFTOOLS_CMD,              # bcftools cmd
        'call',                     # call cmd
        '-v',                       # output variant sites only
        '-m',                       # alternative model for multiallelic and rare-variant calling
        $self->bcf_file->stringify, # input bcf file
    );

    $self->log->debug( "bcftools call command: " . join( ' ', @bcftools_command ) );
    run( \@bcftools_command,
        '>', $output_vcf_file->stringify,
        '2>', $log_file->stringify
    ) or die(
            "Failed to run bcftools call command, see log file: $log_file" );

    $self->vcf_file( $output_vcf_file );
    return;
}

=head2 target_region_vcf_file

Produce a vcf file which only looks at the target region we are interested in.
Any variants not overlapping the target region will be filtered out.

=cut
sub target_region_vcf_file {
    my ( $self ) = @_;
    $self->log->info('Producing target region vcf file');

    # convert vcf to bcf so we can index / filter it
    my $bcf_file = $self->dir->file('analysis.bcf')->absolute;
    my $log_file = $self->dir->file( 'generate_target_region_vcf_file.log' )->absolute;
    my @vcf_to_bcf_command = (
        $BCFTOOLS_CMD,              # bcftools cmd
        'view',                     # view cmd
        '-O', 'b',                  # output is compressed bcf
        $self->vcf_file->stringify, # input bcf file
    );
    $self->log->debug( "vcf to bcf command: " . join( ' ', @vcf_to_bcf_command ) );
    run( \@vcf_to_bcf_command,
        '>', $bcf_file->stringify,
        '2>', $log_file->stringify
    ) or die(
            "Failed to convert vcf to bcf, see log file: $log_file" );

    # index the bcf file
    my @index_bcf_command = (
        $BCFTOOLS_CMD,              # bcftools cmd
        'index',                    # index cmd
        $bcf_file->stringify,       # input bcf file
    );
    $self->log->debug( "bcftools index command: " . join( ' ', @index_bcf_command ) );
    run( \@index_bcf_command,
        '2>>', $log_file->stringify
    ) or die(
            "Failed to index bcf file, see log file: $log_file" );

    # produce vcf filtered to the target region
    my $target_string = $self->target_chr . ":"
        . ( $self->target_start - $self->target_region_padding ) . "-"
        . ( $self->target_end + $self->target_region_padding );
    my $filtered_vcf_file = $self->dir->file('filtered_analysis.vcf')->absolute;
    my @filter_vcf_command = (
        $BCFTOOLS_CMD,              # bcftools cmd
        'view',                     # view cmd
        '-r', $target_string,       # target region
        $bcf_file->stringify,       # input bcf file
    );
    $self->log->debug( "bcftools view filter command: " . join( ' ', @filter_vcf_command ) );
    run( \@filter_vcf_command,
        '>', $filtered_vcf_file->stringify,
        '2>>', $log_file->stringify
    ) or die(
            "Failed to filter vcf file, see log file: $log_file" );

    $self->vcf_file_target_region( $filtered_vcf_file );
    return;
}

=head2 variant_effect_predictor

Run the Ensembl variant_effect_predictor.pl script and store the output.

=cut
sub variant_effect_predictor {
    my ( $self ) = @_;
    $self->log->info( 'Running variant_effect_predictor' );

    if ( $self->no_target_region_variants ) {
        $self->log->warn( 'No variants found in target region, not running vep' );
        return;
    }

    my $vep_output = $self->dir->file('variant_effect_output.txt')->absolute;
    my $log_file = $self->dir->file( 'vep.log' )->absolute;
    my @vep_command = (
        'perl',
        $VEP_CMD,                                       # vep cmd
        '--species', $self->species,                    # species
        '--cache',                                      # use cached data
        '--dir_cache', $VEP_CACHE_DIR,                  # directory where cache is stored
        '-i', $self->vcf_file_target_region->stringify, # input vcf file
        '-o', $vep_output->stringify,                   # output file
        '--no_progress',                                # do not show progresss bar
        '--force_overwrite',                            # overwrite output files if they exist
        '--per_gene',                                   # Output the most severe consequence per gene
        '--symbol',                                     # Output gene symbol
        '--canonical',                                  # Mark if transcript is canonical
        '--plugin', 'HTGT::QC::VEPPlugin::MutantProteinSeqs,' . $self->dir->stringify . '/',
                                                        # Use custom plugin to create protein sequence files
    );

    $self->log->debug( "vep command: " . join( ' ', @vep_command ) );
    run( \@vep_command,
        '>', $log_file->stringify
    ) or die(
            "Failed to run variant_effect_predictor.pl, see log file: $log_file" );

    $self->vep_file( $vep_output );
    $self->vep_html_file( $self->dir->file('variant_effect_output.txt_summary.html')->absolute );

    my $ref_seq_file = $self->dir->file('reference.fa')->absolute;
    my $mut_seq_file = $self->dir->file('mutated.fa')->absolute;
    $self->ref_aa_file( $ref_seq_file ) if $self->dir->contains( $ref_seq_file );
    $self->mut_aa_file( $mut_seq_file ) if $self->dir->contains( $mut_seq_file );

    return;
}

=head2 align_reads

Align the read(s) against the reference genome
using bwa mem

=cut
sub align_reads {
    my ( $self ) = @_;
    $self->log->info( "Running bwa mem to align reads, may take a while..." );

    if ( !$self->has_forward_primer_read && !$self->has_reverse_primer_read ) {
        die("Must specify at least a forward or reverse primer read");
    }

    my $query_file = $self->dir->file('primer_reads.fa')->absolute;
    my $query_fh      = $query_file->openw;
    my $query_seq_out = Bio::SeqIO->new( -fh => $query_fh, -format => 'fasta' );
    $query_seq_out->write_seq( $self->forward_primer_read ) if $self->forward_primer_read;
    $query_seq_out->write_seq( $self->reverse_primer_read ) if $self->reverse_primer_read;

    my $sam_file = $self->bwa_mem( $query_file );
    $self->sam_file( $sam_file );
    return;
}

=head2 bwa_mem

Run bwa mem, return the output sam file

=cut
sub bwa_mem {
    my ( $self, $query_file ) = @_;

    my @mem_command = (
        $BWA_MEM_CMD,
        'mem',                                    # align command
        '-O', 2,                                  # reduce gap open penalty ( default 6 )
        $BWA_REF_GENOMES{ lc( $self->species ) }, # target genome file, indexed for bwa
        $query_file->stringify,                   # query file with read sequences
    );

    $self->log->debug( "BWA mem command: " . join( ' ', @mem_command ) );
    my $bwa_output_sam_file = $self->dir->file('alignment.sam')->absolute;
    my $bwa_mem_log_file = $self->dir->file( 'bwa_mem.log' )->absolute;
    run( \@mem_command,
        '>', $bwa_output_sam_file->stringify,
        '2>', $bwa_mem_log_file->stringify
    ) or die(
            "Failed to run bwa mem command, see log file: $bwa_mem_log_file" );

    return $bwa_output_sam_file;
}

=head2 no_target_region_variants

Check vcf file for target region to see if we have any variants

=cut
sub no_target_region_variants {
    my ( $self ) = @_;

    my @variant_lines = grep { !/^#/ } $self->vcf_file_target_region->slurp( chomp => 1 );

    return @variant_lines ? 0 : 1;
}

__PACKAGE__->meta->make_immutable;

1;

__END__
