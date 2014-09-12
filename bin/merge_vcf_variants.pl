#!/usr/bin/env perl
use strict;
use warnings FATAL => 'all';

use HTGT::QC::Util::MergeVariantsVCF;
use Getopt::Long;
use Log::Log4perl ':easy';
use Path::Class;

my $log_level = $WARN;

my ( $vcf_file, $dir, $species );
GetOptions(
    'help'       => sub { pod2usage( -verbose => 1 ) },
    'man'        => sub { pod2usage( -verbose => 2 ) },
    'debug'      => sub { $log_level = $DEBUG },
    'verbose'    => sub { $log_level = $INFO },
    'vcf-file=s' => \$vcf_file,
    'dir=s'      => \$dir,
    'species=s'  => \$species,
) or pod2usage(2);

die('Must specify a vcf file: --vcf-file') unless $vcf_file;
die('Must specify a work dir: --dir') unless $dir;
die('Must specify a species: --species') unless $species;

Log::Log4perl->easy_init( { level => $log_level, layout => '%p %m%n' } );

my $work_dir = dir( $dir )->absolute;
$work_dir->mkpath();

my $qc = HTGT::QC::Util::MergeVariantsVCF->new(
    vcf_file => $vcf_file,
    dir      => $work_dir,
    species  => $species,
);

my $merged_vcf = $qc->create_merged_vcf;

__END__

=head1 NAME

merge_vcf_variants.pl - merge variants in vcf

=head1 SYNOPSIS

  merge_vcf_variants.pl [options]

      --help                      Display a brief help message
      --man                       Display the manual page
      --debug                     Debug output
      --verbose                   Verbose output
      --vcf-file                  VCF file we are to work on
      --dir                       Directory where work files are sent
      --species                   Species

=head1 DESCRIPTION

Take all the variants in VCF file and attempt to merge all the variants into one.
Clearly the VCF file should only contain variants from a specific and small region.

=cut
