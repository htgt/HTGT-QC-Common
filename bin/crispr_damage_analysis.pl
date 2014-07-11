#!/usr/bin/env perl
use strict;
use warnings FATAL => 'all';

use HTGT::QC::Util::CrisprDamageVEP;
use Getopt::Long;
use Log::Log4perl ':easy';
use IPC::Run 'run';
use Bio::SeqIO;
use Pod::Usage;
use Path::Class;
use Const::Fast;

const my $EXTRACT_SEQ_CMD => $ENV{EXTRACT_SEQ_CMD}
    // '/software/badger/bin/extract_seq';

my $log_level = $INFO;

my ( $seq_filename, $scf_filename, $target_start, $target_end, $target_chr, $species, $dir );
GetOptions(
    'help'            => sub { pod2usage( -verbose => 1 ) },
    'man'             => sub { pod2usage( -verbose => 2 ) },
    'debug'           => sub { $log_level = $DEBUG },
    'sequence-file=s' => \$seq_filename,
    'scf-file=s'      => \$scf_filename,
    'target-start=i'  => \$target_start,
    'target-end=i'    => \$target_end,
    'target-chr=s'    => \$target_chr,
    'species=s'       => \$species,
    'dir=s'           => \$dir,
) or pod2usage(2);

pod2usage('Must provide crispr target location information')
    if !$target_start || !$target_end || !$target_chr || !$species;

Log::Log4perl->easy_init( { level => $log_level, layout => '%p %m%n' } );

my $work_dir = dir( $dir )->absolute;

my $seq_file;
if ( $scf_filename ) {
    my $scf_file = file( $scf_filename )->absolute;
    $seq_file = scf_to_fasta( $scf_file ); 
}
elsif ( $seq_filename ) {
    $seq_file = file( $seq_filename )->absolute;
}
else {
    pod2usage( 'Must provide a sequence file or scf file' );
}


my $seq_io = Bio::SeqIO->new( -fh => $seq_file->openr, -format => 'Fasta' );
my $bio_seq = $seq_io->next_seq;

my %params = (
    species             => $species,
    dir                 => $work_dir,
    target_start        => $target_start,
    target_end          => $target_end,
    target_chr          => $target_chr,
    forward_primer_read => $bio_seq,
);

my $qc = HTGT::QC::Util::CrisprDamageVEP->new( %params );

$qc->analyse;

sub scf_to_fasta {
    my $scf_file = shift;
    INFO( 'Converting scf file to fasta file' );

    my $read_seq = $work_dir->file('read_seq.fa')->absolute;
    my @extract_seq_command = (
        $EXTRACT_SEQ_CMD,
        '-scf',                         # align command
        '-fasta_out',                   # reduce gap open penalty ( default 6 )
        $scf_file->stringify,           # query file with read sequences
    );

    my $extract_seq_log_file = $work_dir->file( 'extract_seq.log' )->absolute;
    run( \@extract_seq_command,
        '>', $read_seq->stringify,
        '2>', $extract_seq_log_file->stringify
    ) or die(
            "Failed to run extract_seq command, log file: $extract_seq_log_file" );

    return $read_seq;
}

# TODO
# What to return from script?
# Maybe location of work dir if its something we create
# Otherwise some sort of status ... not sure what form this will take
# json??
#$work_dir->mkpath(); # TODO should be do with?

__END__

=head1 NAME

crispr_damage_analysis.pl - Analyse crispr damage using one primer read 

=head1 SYNOPSIS

  crispr_damage_analysis.pl [options]

      --help                      Display a brief help message
      --man                       Display the manual page
      --debug                     Debug output
      --sequence-file             File with primer read sequence
      --scf-file                  File with primer read trace sequence
      --target-start              * Start coordinate of crispr target region
      --target-end                * End coordinate of crispr target region
      --target-chr                * Chromosome name of crispr target region
      --species                   * Species, either Mouse or Human supported
      --dir                       * Directory where work files are sent

The parameters marked with a * are required.
You must specify a sequence-file or a scf-file.
The sequence file maybe Fasta or Genbank, only the first sequence in the
file will be used.

=head1 DESCRIPTION

Analyse the possible damage caused by a crispr or crispr pair to a specific
target region ( where the crispr targets ).

Input is a primer read that runs across the target site, outputs include:
- Alignment of read against genome.
- Pileup of read against genome.
- VCF file, only for target region.
- Output from Ensembl Variant Effect Predictor.
- If variant found, reference and mutant protein sequence for targeted gene transcript.

=cut
