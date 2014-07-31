#!/usr/bin/env perl
use strict;
use warnings FATAL => 'all';

=head1 NAME

10-htgt-qc-util-merge-variants-vcf

=head1 DESCRIPTION

Black box testing of HTGT::QC::Util::MergeVariantsVCF
Checking a vcf file plus some standard parameters produces the expected merged vcf output.

=cut

use Test::Most;
use Path::Class;
use FindBin;
use YAML::Any qw( LoadFile );
use Log::Log4perl ':levels';

Log::Log4perl->easy_init( $WARN );

use_ok 'HTGT::QC::Util::MergeVariantsVCF';

my $data_dir = dir($FindBin::Bin)->absolute->subdir('test_data/merge_vcf');

{
    note( 'Test MergeVariantsVCF generated the expeccted merged VCF file' );

    # setup multiple matches scf and fasta files to test against
    for my $test ( 1..7 ) {
        my $temp_dir = Path::Class::tempdir(CLEANUP => 1);
        my $vcf_file = $data_dir->file( $test . '.vcf' )->absolute;
        my $expected_results = LoadFile( $data_dir->file( $test . '.yaml' )->absolute );
        note( 'Test vcf: ' . $expected_results->{name} );

        ok my $qc = HTGT::QC::Util::MergeVariantsVCF->new(
            species  => 'Human',
            vcf_file =>  $vcf_file,
            dir      => $temp_dir->absolute,
        ), "Constructor succeeds";

        isa_ok $qc, 'HTGT::QC::Util::MergeVariantsVCF', "Object is of correct type: ";

        lives_ok {
            $qc->create_merged_vcf
        } 'can call create_merged_vcf';

        if ( !$expected_results->{can_merge} ) {
            ok !$qc->merged_vcf_file, 'we have no merged vcf file';
            next;
        }

        ok $qc->merged_vcf_file, 'we have a merged vcf file';
        ok my @variants = map( [ split /\t/ ], grep( !/^#/, $qc->merged_vcf_file->slurp( chomp => 1 ) ) ),
            'can grab variants from merged vcf file';
        
        is scalar( @variants ), 1, 'we have only one variant and the'; 
        is $variants[0][1], $expected_results->{start}, '.. start position is correct';
        is $variants[0][3], $expected_results->{ref_seq}, '.. reference sequence is correct';
        is $variants[0][4], $expected_results->{alt_seq}, '.. alternate sequence is correct';
    }

}

done_testing;
