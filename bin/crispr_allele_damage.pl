#!/usr/bin/env perl
use strict;
use warnings FATAL => 'all';

use HTGT::QC::Util::CrisprAlleleDamage;
use HTGT::QC::Util::CigarParser;
use LIMS2::Model;
use Getopt::Long;
use Log::Log4perl ':easy';
use Bio::SeqIO;
use Pod::Usage;
use Path::Class;
use feature qw( say );

my $log_level = $WARN;

my ( $well_name, $forward_primer_name, $reverse_primer_name, $genomic_region_file, $primer_reads_file, $dir );
GetOptions(
    'help'                  => sub { pod2usage( -verbose    => 1 ) },
    'man'                   => sub { pod2usage( -verbose    => 2 ) },
    'debug'                 => sub { $log_level = $DEBUG },
    'verbose'               => sub { $log_level = $INFO },
    'well_name=s'           => \$well_name,
    'forward_primer_name=s' => \$forward_primer_name,
    'reverse_primer_name=s' => \$reverse_primer_name,
    'genomic_region_file=s' => \$genomic_region_file,
    'primer_reads_file=s'   => \$primer_reads_file,
    'dir=s'                 => \$dir,
) or pod2usage(2);

Log::Log4perl->easy_init( { level => $log_level, layout => '%p %m%n' } );
#my $model = LIMS2::Model->new( user => 'lims2', audit_user => $ENV{USER}.'@sanger.ac.uk' );
my $parser =  HTGT::QC::Util::CigarParser->new(
        primers => [ $forward_primer_name, $reverse_primer_name ] );

# TODO: make sure parameter specified

die('Must specify a well name') unless $well_name;

my $primer_reads_io = Bio::SeqIO->new( -file => $primer_reads_file, -format => 'Fasta' );

my %primer_reads;
while ( my $seq = $primer_reads_io->next_seq ) {
    my $res = $parser->parse_query_id( $seq->display_name );

    if ( $res->{primer} eq $forward_primer_name ) {
        $primer_reads{ $res->{well_name} }{forward} = $seq;
    }
    elsif ( $res->{primer} eq $reverse_primer_name ) {
        $primer_reads{ $res->{well_name} }{reverse} = $seq;
    }
    else {
        ERROR( "Unknown primer read name $res->{primer}" );
    }
}

my $work_dir = dir( $dir )->absolute;
my $genomic_region_io = Bio::SeqIO->new( -file => $genomic_region_file, -format => 'Fasta' );

my %params = (
    genomic_region      => $genomic_region_io->next_seq,
    forward_primer_name => $forward_primer_name,
    reverse_primer_name => $reverse_primer_name,
    dir                 => $work_dir,
    cigar_parser        => $parser,
);

if ( exists $primer_reads{$well_name} ){
    my $well_reads = $primer_reads{$well_name};
    $params{forward_primer_read} = $well_reads->{forward} if exists $well_reads->{forward};
    $params{reverse_primer_read} = $well_reads->{reverse} if exists $well_reads->{reverse};
}
else {
    die("No primer reads for well $well_name\n");
}

my $qc = HTGT::QC::Util::CrisprAlleleDamage->new( %params );

my $analysis = $qc->analyse;

my $trim_five_prime = 100;
my $seq_length = 230;
say substr( $analysis->{forward}{full_match_string}, $trim_five_prime, $seq_length );
say substr( $analysis->{forward}{query_align_str}, $trim_five_prime, $seq_length );
say substr( $analysis->{forward}{target_align_str}, $trim_five_prime, $seq_length );
say substr( $analysis->{reverse}{query_align_str}, $trim_five_prime, $seq_length );
say substr( $analysis->{reverse}{full_match_string}, $trim_five_prime, $seq_length );

__END__

=head1 NAME

crispr_allele_damage.pl - driver script for crispr allele dmg module 

=head1 SYNOPSIS

  crispr_allele_damage.pl [options]

      --help                      Display a brief help message
      --man                       Display the manual page
      --debug                     Debug output
      --verbose                   Verbose output
      --well_name                 Name of specific well we are analysing
      --forward_primer_name       Name of forward primer
      --reverse_primer_name       Name of reverse primer
      --genomic_region_file       File with genomic region sequence ( Fasta )
      --primer_reads_file         File with primer read sequences ( Fasta )
      --dir                       Directory where work files are sent

=head1 DESCRIPTION


=head1 TODO

=cut
