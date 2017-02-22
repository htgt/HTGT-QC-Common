package HTGT::QC::Util::CrisprDamageVEP;
## no critic(RequireUseStrict,RequireUseWarnings)
{
    $HTGT::QC::Util::CrisprDamageVEP::VERSION = '0.050';
}
## use critic


=head1 NAME

HTGT::QC::Util::CrisprDamageVEP

=head1 DESCRIPTION

Identify damage caused by crispr(s) on the second allele.
Compare wildtype genomic sequence of area around crispr(s) target site with the sequence
from primer reads that flank this target site.
Try to predict the effect of the damage using Ensemble's Varient Effect Predictor (VEP) software.

=cut

use Moose;
use HTGT::QC::Util::DrawPileupAlignment;
use HTGT::QC::Util::MergeVariantsVCF;
use Bio::SeqIO;
use MooseX::Types::Path::Class::MoreCoercions qw/AbsDir/;
use IPC::Run 'run';
use List::MoreUtils qw( any );
use HTGT::QC::Constants qw(
    $BWA_MEM_CMD
    $SAMTOOLS_CMD
    $BCFTOOLS_CMD
    $VEP_CMD
    $VEP_CACHE_DIR
    %BWA_REF_GENOMES
    %CURRENT_ASSEMBLY
);
use namespace::autoclean;

with qw( MooseX::Log::Log4perl );

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
    'ref_aa_file', 'mut_aa_file', 'non_merged_vcf_file'
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

has merge_vcf_util => (
    is  => 'rw',
    isa => 'HTGT::QC::Util::MergeVariantsVCF',
);

has variant_type => (
    is      => 'rw',
    isa     => 'Str',
    default => 'no-call',
);

has variant_size => (
    is  => 'rw',
    isa => 'Int',
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
    #$self->remove_reads_not_overlapping_target;
    $self->run_mpileup;
    $self->parse_pileup_file;
    $self->variant_calling;
    $self->target_region_vcf_file;
    $self->merge_variants;
    $self->call_variant_type;
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
    $self->log->info('Converting SAM file to BAM file');

    my @samtools_view_command = (
        $SAMTOOLS_CMD,
        'view',                     # view command
        '-b',                       # output is compressed BAM file
        '-F', 2048,                 # filter alignments with bit present in secondary alignment
        $self->sam_file->stringify,
    );

    $self->log->debug( "samtools view command: " . join( ' ', @samtools_view_command ) );

    my $bam_file = $self->dir->file('alignment.bam')->absolute;
    my $log_file = $self->dir->file( 'sam_to_bam.log' )->absolute;
    run( \@samtools_view_command,
        '>',  $bam_file->stringify,
        '2>', $log_file->stringify
    ) or die (
            "Failed to run bwa sam to bam command, see log file: $log_file" );

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

Run mpileup, input is sorted bam file.
We want pileup and bcf output.

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
        $self->bam_file->stringify,
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
        $self->bam_file->stringify,
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

    my $alignment_count = 0;
    foreach my $seq_type ( qw(forward reverse) ){
        $alignment_count++ if exists $pileup_parser->seqs->{$seq_type};
    }
    $self->num_target_region_alignments( $alignment_count );

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
        #'-m',                       # alternative model for multiallelic and rare-variant calling
        '-c',                       # original calling method
        '-p', 1,                    # pval threshhold to accept variant, 1 means accept all
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

=head2 merge_variants

Attempt to merge all the variants from the target region vcf file into one variant.
This is hack that lets us run the resultant merged vcf file through VEP
which will then produce one mutant protein sequence ( instead of multiple sequences
for each variant ). The output from VEP when doing this is not optimal.

We should find another way to produce the reference and mutant protein sequences and
stop merging the variants.

=cut
sub merge_variants {
    my ( $self ) = @_;

    my $work_dir = $self->dir->subdir( 'merge_vcf' );
    $work_dir->mkpath;
    my $merge_vcf_util = HTGT::QC::Util::MergeVariantsVCF->new(
        vcf_file => $self->vcf_file_target_region->absolute,
        dir      => $work_dir,
        species  => $self->species,
    );

    my $merged_vcf = $merge_vcf_util->create_merged_vcf;
    $self->merge_vcf_util( $merge_vcf_util );

    if ( $merged_vcf ) {
        $self->non_merged_vcf_file( $self->vcf_file_target_region );
        $self->vcf_file_target_region( $merged_vcf );
    }

    return;
}

=head2 call_variant_type

Attempt to make a overall call of the variant type to aid in human analysis of results.
Can only do this when variant is supported by 2 reads.
Use the MergeVariantsVCF object to get the parsed variants details from the vcf file.

=cut
sub call_variant_type {
    my ( $self ) = @_;

    # if we don't have 2 reads overlapping target region do nothing
    return unless $self->num_target_region_alignments == 2;
    # if this object has not been created do nothing
    return unless $self->merge_vcf_util;

    # If no variants then call it wildtype unless both reads do not completely cover
    # the target region, in that case we have to make a no-call
    if ( $self->merge_vcf_util->no_variants ) {
        return if $self->reads_do_not_cover_target_region;
        $self->log->info( 'No variants in target region, setting variant type to: wildtype' );
        $self->variant_type( 'wild_type' );
        return;
    }
    my @variants = $self->merge_vcf_util->all_variants;

    if ( any{ $_->[7] =~ /DP=1/ } @variants ) {
        $self->log->debug( 'Have variants supported only by 1 read, can not set variant type' );
        return;
    }

    my @indel_variants = grep{ $_->[7] =~ /^INDEL/ } @variants;
    if ( !@indel_variants ) {
        $self->log->debug( 'No INDEL variants in target region, not making variant type call' );
        return;
    }
    elsif ( any{ $_->[7] =~ /IDV=1/ } @indel_variants ) {
        $self->log->debug( 'We have INDEL variant supported by 1 read, not not set variant type' );
        return;
    }

    my $indel_bases = 0;
    for my $var ( @indel_variants ) {
        my $ref_seq_length = length( $var->[3] );
        my $alt_seq_length = length( $var->[4] );
        $indel_bases += $alt_seq_length - $ref_seq_length;
    }

    $self->variant_size( $indel_bases );
    if ( $indel_bases == 0 ) {
        $self->log->info( "Have 0 base overall change, inframe variant" );
        $self->variant_type( 'in-frame' );
        return;
    }

    if ( $indel_bases % 3 ) {
        $self->log->info( "Have $indel_bases change, frameshift variant" );
        $self->variant_type( 'frameshift' );
    }
    else {
        $self->log->info( "Have $indel_bases change, inframe variant" );
        $self->variant_type( 'in-frame' );
    }

    return;
}

=head2 reads_do_not_cover_target_region

A hacky way to check if both the forward and reverse read completely cover the target region.
I only do it this way because I have already drawn up the alignment in the DrawPileupAlignment
object. ( Really should use the SAM file to check the extent of the read alignment )

=cut
sub reads_do_not_cover_target_region {
    my ( $self, $json ) = @_;

    my $fwd_read_seq = $self->pileup_parser->seqs->{forward};
    my $rev_read_seq = $self->pileup_parser->seqs->{reverse};

    # work out target region start relative to fwd and rev read sequences we have
    my $relative_target_region_start = $self->target_start - $self->pileup_parser->genome_start;
    my $target_region_length = ( $self->target_end - $self->target_start ) + 1;
    my $fwd_read_target_region = substr( $fwd_read_seq, $relative_target_region_start, $target_region_length );
    my $rev_read_target_region = substr( $rev_read_seq, $relative_target_region_start, $target_region_length );

    if ( $fwd_read_target_region =~ /X+/ ) {
        $self->log->debug( "Fwd read does not cover target region: $fwd_read_target_region" );
        return 1;
    }
    elsif ( $rev_read_target_region =~ /X+/ ) {
        $self->log->debug( "Rev read does not cover target region: $rev_read_target_region" );
        return 1;
    }

    return 0;
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
        $VEP_CMD,                                        # vep cmd
        '--species', $self->species,                     # species
        '--assembly', $CURRENT_ASSEMBLY{$self->species}, # assembly
        '--cache',                                       # use cached data
        '--dir_cache', $VEP_CACHE_DIR,                   # directory where cache is stored
        '-i', $self->vcf_file_target_region->stringify,  # input vcf file
        '-o', $vep_output->stringify,                    # output file
        '--no_progress',                                 # do not show progresss bar
        '--force_overwrite',                             # overwrite output files if they exist
        '--per_gene',                                    # Output the most severe consequence per gene
        '--symbol',                                      # Output gene symbol
        '--canonical',                                   # Mark if transcript is canonical
        '--plugin', 'HTGT::QC::VEPPlugin::MutantProteinSeqs,' . $self->dir->stringify . '/',
                                                         # Use custom plugin to create protein sequence files
                                                         # pass in work dir as argument so plugin knows where to
                                                         # put sequence files
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
