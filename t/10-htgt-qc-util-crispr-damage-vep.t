#!/usr/bin/env perl
use strict;
use warnings FATAL => 'all';

=head1 NAME

10-htgt-qc-util-draw-crispr-damage-vep

=head1 DESCRIPTION

Black box testing of HTGT::QC::Util::CrisprDamageVEP
Check the input reads and other parameters produce the expected vcf and vep output

=cut

use Test::Most;
use Path::Class;
use FindBin;
use File::Compare qw( compare_text compare );
use Log::Log4perl ':levels';
use YAML::Any qw( LoadFile );

Log::Log4perl->easy_init( $ERROR );

use_ok 'HTGT::QC::Util::CrisprDamageVEP';

my $base_data_dir = dir($FindBin::Bin)->absolute->subdir('test_data/crispr_damage_vep');

{
    note( 'Testing creation of alignment strings from pileup files' );

    # sample from 1EC0414A-0B45-11E4-B117-24522CEFA7E5 ( Human )
    # 1: concordant 4 base pair insertion in target region ( A01 )
    # 2: concordant 53 base pair deletion in target region ( D08 )
    # 3: complicated insertions / deletions / mismatches in target region ( D11 )
    # 4: one read, mulitiple insertions and few mismatches ( H02 )
    # samples from 1CE43C00-0B40-11E4-AADE-20522CEFA7E5 ( Mouse )
    # 5: concordant insertions, deletions and mismatches, all within small area
    # 6: no variants in target region
    for my $test ( 1..6 ) {
        note( "Test set $test" );
        my $temp_dir = Path::Class::tempdir(CLEANUP => 1);

        my $data_dir = $base_data_dir->subdir( $test );
        my $params   = LoadFile( $data_dir->file( 'params.yaml' )->absolute );
        # NOTE: sending in alignment file for reads instead of the actual reads to
        #       save time, running bwa mem multiple times is time consuming!
        my $sam_file = $data_dir->file( 'alignment.sam' )->absolute;
        my $vcf_file = $data_dir->file( 'filtered_analysis.vcf' )->absolute;
        my $vep_file = $data_dir->file( 'variant_effect_output.txt' )->absolute;
        my $pileup_file = $data_dir->file( 'analysis.pileup' )->absolute;

        my %params = (
            target_start => $params->{start},
            target_end   => $params->{end},
            target_chr   => $params->{chr},
            dir          => $temp_dir,
            species      => $params->{species},
            sam_file     => $sam_file,
        );

        ok my $qc = HTGT::QC::Util::CrisprDamageVEP->new( %params ), 'can create CrisprDamageVEP object';
        isa_ok $qc, 'HTGT::QC::Util::CrisprDamageVEP', "Object is of correct type: ";

        lives_ok{ 
            $qc->analyse
        } 'can call analyse';

        ok compare_text(
              $vcf_file->openr,                                 # newly generated filtered vcf file
              $qc->vcf_file_target_region->openr,               # expected filtered vcf file
              sub { return 0 if $_[0] =~ /^#/; $_[0] ne $_[1] } # line comparison function, ignore comments
           ) == 0
           , 'we have expected variants in filtered vcf file';

        ok compare(
              $pileup_file->openr,     # newly generated pileup file
              $qc->pileup_file->openr, # expected pileup file
           ) == 0
           , 'we have expected pileup file data';

        next unless $data_dir->contains( $vep_file );

        ok compare_text(
              $vep_file->openr,                                 # newly generated vep file
              $qc->vep_file->openr,                             # expected vep file
              sub { return 0 if $_[0] =~ /^#/; $_[0] ne $_[1] } # line comparison function, ignore comments
           ) == 0
           , 'we have expected output from vep program';

        is $qc->variant_type, $params->{expected_variant_type}, 'frameshift have expected variant type';
        is $qc->variant_size, $params->{expected_variant_size}, 'we have expected variant size';

    }
}

done_testing;
