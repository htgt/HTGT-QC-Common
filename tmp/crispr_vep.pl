#!/usr/bin/env perl
use strict;
use warnings FATAL => 'all';

use HTGT::QC::Util::CrisprDamageVEP;
use HTGT::QC::Util::CigarParser;
use LIMS2::Model;
use Getopt::Long;
use Log::Log4perl ':easy';
use Bio::SeqIO;
use Pod::Usage;
use Path::Class;
use feature qw( say );

my $log_level = $WARN;

my ( $forward_primer_name, $reverse_primer_name, $primer_reads_file, $dir, $sam_file, $well_id );
GetOptions(
    'help'                  => sub { pod2usage( -verbose    => 1 ) },
    'man'                   => sub { pod2usage( -verbose    => 2 ) },
    'debug'                 => sub { $log_level = $DEBUG },
    'verbose'               => sub { $log_level = $INFO },
    'es_well_id=s'          => \$well_id,
    'forward_primer_name=s' => \$forward_primer_name,
    'reverse_primer_name=s' => \$reverse_primer_name,
    'primer_reads_file=s'   => \$primer_reads_file,
    'dir=s'                 => \$dir,
    'sam_file=s'            => \$sam_file,
) or pod2usage(2);

die('Must specify a well id') unless $well_id;

my $model = LIMS2::Model->new( user => 'lims2' );
Log::Log4perl->easy_init( { level => $log_level, layout => '%p %m%n' } );
$forward_primer_name //= 'SF1';
$reverse_primer_name //= 'SR1';
my $parser =  HTGT::QC::Util::CigarParser->new(
        primers => [ $forward_primer_name, $reverse_primer_name ] );

my $well = $model->retrieve_well( { id => $well_id } );
my $well_name = $well->name;
my $crispr = crispr_for_well( $well );

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
$work_dir->mkpath();
my %params = (
    species      => 'Human',
    dir          => $work_dir,
    target_start => $crispr->start,
    target_end   => $crispr->end,
    target_chr   => $crispr->chr_name,
);

$params{sam_file} = $sam_file if $sam_file;

if ( exists $primer_reads{$well_name} ){
    my $well_reads = $primer_reads{$well_name};
    $params{forward_primer_read} = $well_reads->{forward} if exists $well_reads->{forward};
    $params{reverse_primer_read} = $well_reads->{reverse} if exists $well_reads->{reverse};
}
else {
    die("No primer reads for well $well_name\n");
}

my $qc = HTGT::QC::Util::CrisprDamageVEP->new( %params );

$qc->analyse;

sub crispr_for_well {
    my ( $well ) = @_;

    my ( $left_crispr_well, $right_crispr_well ) = $well->left_and_right_crispr_wells;

    if ( $left_crispr_well && $right_crispr_well ) {
        my $left_crispr  = $left_crispr_well->crispr;
        my $right_crispr = $right_crispr_well->crispr;

        my $crispr_pair = $model->schema->resultset('CrisprPair')->find(
            {
                left_crispr_id  => $left_crispr->id,
                right_crispr_id => $right_crispr->id,
            }
        );

        unless ( $crispr_pair ) {
            die(
                "Unable to find crispr pair: left crispr $left_crispr, right crispr $right_crispr" );
        }
        DEBUG("Crispr pair for well $well: $crispr_pair" );

        return $crispr_pair;
    }
    elsif ( $left_crispr_well ) {
        my $crispr = $left_crispr_well->crispr;
        DEBUG("Crispr pair for $well: $crispr" );
        return $crispr;
    }
    else {
        die( "Unable to determine crispr pair or crispr for well $well" );
    }

    return;
}

__END__

=head1 NAME

crispr_vep.pl - ??

=head1 SYNOPSIS

  crispr_vep.pl [options]

      --help                      Display a brief help message
      --man                       Display the manual page
      --debug                     Debug output
      --verbose                   Verbose output
      --well_name                 Name of specific well we are analysing
      --forward_primer_name       Name of forward primer
      --reverse_primer_name       Name of reverse primer
      --primer_reads_file         File with primer read sequences ( Fasta )
      --dir                       Directory where work files are sent

=head1 DESCRIPTION


=head1 TODO

=cut
