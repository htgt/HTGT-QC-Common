#!/usr/bin/env perl
use strict;
use warnings FATAL => 'all';

use HTGT::QC::Util::GeneratePrimersAttempts;
use Getopt::Long;
use Log::Log4perl ':easy';
use Path::Class;

my $log_level = $WARN;

my ($seq_file,               $dir,                      $species,
    $start,                  $end,                      $strand,
    $chromosome,             $p3_config,                $target_string,
    $five_prime_region_size, $five_prime_region_offset, $three_prime_region_size,
    $three_prime_region_offset
);
GetOptions(
    'help'            => sub { pod2usage( -verbose => 1 ) },
    'man'             => sub { pod2usage( -verbose => 2 ) },
    'debug'           => sub { $log_level = $DEBUG },
    'verbose'         => sub { $log_level = $INFO },
    'dir=s'           => \$dir,
    'species=s'       => \$species,
    'start=i'         => \$start,
    'end=i'           => \$end,
    'strand=i'        => \$strand,
    'chromosome=i'    => \$chromosome,
    'p3-config=s'     => \$p3_config,
) or pod2usage(2);

$p3_config //= '/nfs/team87/farm3_lims2_vms/conf/primer3_design_create_config.yaml';
my $p3_file = file( $p3_config )->absolute;

$five_prime_region_size    //= 1000;
$five_prime_region_offset  //= 100;
$three_prime_region_size   //= 1000;
$three_prime_region_offset //= 100;

Log::Log4perl->easy_init( { level => $log_level, layout => '%p %m%n' } );

my $work_dir = dir( $dir )->absolute;
$work_dir->mkpath();

my $util = HTGT::QC::Util::GeneratePrimersAttempts->new(
    base_dir                  => $work_dir,
    species                   => $species,
    strand                    => $strand,
    chromosome                => $chromosome,
    target_start              => $start,
    target_end                => $end,
    five_prime_region_size    => $five_prime_region_size,
    five_prime_region_offset  => $five_prime_region_offset,
    three_prime_region_size   => $three_prime_region_size,
    three_prime_region_offset => $three_prime_region_offset,
    primer3_config_file       => $p3_file,
);

my $primer_data = $util->find_primers;

__END__

=head1 NAME

generate_primers.pl - run script for HTGT::QC::Util::GeneratePrimersAttempts

=head1 SYNOPSIS

  generate_primers.pl [options]

      --help                      Display a brief help message
      --man                       Display the manual page
      --debug                     Debug output
      --verbose                   Verbose output
      --dir                       Directory where work files are sent
      --species                   Species
      --start                     Start coordinate for target region
      --end                       End coordinate for  target region
      --strand                    Strand of target region
      --chromosome                Chromosome of target region
      --p3-config                 Config file for Primer3, defaults to design create config file


=head1 DESCRIPTION

Runner script for GeneratePrimersAttempts module.
Currently work in progress.

=cut
