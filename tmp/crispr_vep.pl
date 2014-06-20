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

my ( $well_name, $forward_primer_name, $reverse_primer_name, $primer_reads_file, $dir,
    $crispr_es_qc_well_id, $commit, $sam_file );
GetOptions(
    'help'                  => sub { pod2usage( -verbose    => 1 ) },
    'man'                   => sub { pod2usage( -verbose    => 2 ) },
    'debug'                 => sub { $log_level = $DEBUG },
    'verbose'               => sub { $log_level = $INFO },
    'well_name=s'           => \$well_name,
    'forward_primer_name=s' => \$forward_primer_name,
    'reverse_primer_name=s' => \$reverse_primer_name,
    'primer_reads_file=s'   => \$primer_reads_file,
    'dir=s'                 => \$dir,
    'sam_file=s'            => \$sam_file,
    'crispr_qc_id=i'        => \$crispr_es_qc_well_id,
    'commit'                => \$commit,
) or pod2usage(2);

die('Must specify a well name') unless $well_name;

my $model = LIMS2::Model->new( user => 'lims2' );
Log::Log4perl->easy_init( { level => $log_level, layout => '%p %m%n' } );
$forward_primer_name //= 'SF1';
$reverse_primer_name //= 'SR1';
my $parser =  HTGT::QC::Util::CigarParser->new(
        primers => [ $forward_primer_name, $reverse_primer_name ] );

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
    #target_start => 48018114, # MSH6
    target_end   => 48018176,
    target_start => 47637239, #MSH2
    #target_end => 47637303,
    #target_start => 203678601,
    #target_end   => 203678646,
    target_chr   => 2,
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

if ( $crispr_es_qc_well_id ) {
    my $vcf_data = $qc->vcf_file->slurp;

    # grab crispr_es_qc_well record
    my $crispr_es_qc_well = $model->schema->resultset('CrisprEsQcWell')->find( { id => $crispr_es_qc_well_id } );

    FATAL( "No crispr es qc well record with id $crispr_es_qc_well_id" ) unless $crispr_es_qc_well;

    if ( $crispr_es_qc_well->well->name ne $well_name ) {
        FATAL( "Specified well name $well_name and the crispr_es_qc_well do not match: "
                . $crispr_es_qc_well->well->name );
    }

    $model->txn_do(
        sub {
            $crispr_es_qc_well->update( { vcf_file => $vcf_data } );
            unless ( $commit ) {
                WARN("non-commit mode, rollback");
                $model->txn_rollback;
            }
        }
    );
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
