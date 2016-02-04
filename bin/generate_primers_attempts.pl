#!/usr/bin/env perl
use strict;
use warnings FATAL => 'all';

use HTGT::QC::Util::GeneratePrimersAttempts;
use Getopt::Long;
use Log::Log4perl ':easy';
use Path::Class;
use YAML::Any qw( LoadFile );
use JSON;
use Pod::Usage;

my $log_level = $WARN;

my ( $dir, $species, $start, $end, $strand, $chromosome, $p3_config, $five_prime_region_size,
    $five_prime_region_offset, $three_prime_region_size, $three_prime_region_offset );

# Too many options now! put them in a params yaml file and write results to output-file
my ($output_file, $params_file);
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
    'output-file=s'   => \$output_file,
    'params-file=s'   => \$params_file,
) or pod2usage(2);

Log::Log4perl->easy_init( { level => $log_level, layout => '%p %m%n' } );

my $util;
my $output = file( $output_file )->openw
    or die "Could not open file $output_file for writing - $!";

if($params_file){
    my $params = LoadFile($params_file);
    $params->{base_dir} = dir( $params->{base_dir} );
    $params->{primer3_config_file} = file( $params->{primer3_config_file} );
    $util = HTGT::QC::Util::GeneratePrimersAttempts->new( $params );
}
else{

    $p3_config //= '/nfs/team87/farm3_lims2_vms/conf/primer3_design_create_config.yaml';
    my $p3_file = file( $p3_config )->absolute;

    $five_prime_region_size    //= 1000;
    $five_prime_region_offset  //= 100;
    $three_prime_region_size   //= 1000;
    $three_prime_region_offset //= 100;

    my $work_dir = dir( $dir )->absolute;
    $work_dir->mkpath();

    $util = HTGT::QC::Util::GeneratePrimersAttempts->new(
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
}

my ($primer_data, $seq) = $util->find_primers;
my $output_info = {
    primer_data => $primer_data,
    seq         => $seq->seq,
    five_prime_region_offset  => $util->five_prime_region_offset,
    five_prime_region_size    => $util->five_prime_region_size,
    three_prime_region_offset => $util->three_prime_region_offset,
    three_prime_region_size   => $util->three_prime_region_size,
};

print $output ( encode_json $output_info );

__END__

=head1 NAME

generate_primers.pl - run script for HTGT::QC::Util::GeneratePrimersAttempts

=head1 SYNOPSIS

  generate_primers.pl [options]

      --help                      Display a brief help message
      --man                       Display the manual page
      --debug                     Debug output
      --verbose                   Verbose output
      --output-file               File to write primers and target sequence to (in json)
      --params-file               Yaml file containing all params to pass to constructor of
                                  GeneratePrimersAttempts

      OR provide the following args and default settings will be used:

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
