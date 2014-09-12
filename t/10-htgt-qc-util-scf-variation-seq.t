#!/usr/bin/env perl
use strict;
use warnings FATAL => 'all';

=head1 NAME

10-htgt-qc-util-scf-variation-seq

=head1 DESCRIPTION

Black box testing of HTGT::QC::Util::SCFVariationSeq
Checking a scf file plus some standard parameters produces the expected fasta file output.

=cut

use Test::Most;
use Path::Class;
use FindBin;
use File::Compare;
use Log::Log4perl ':levels';

Log::Log4perl->easy_init( $WARN );

use_ok 'HTGT::QC::Util::SCFVariationSeq';

my $data_dir = dir($FindBin::Bin)->absolute->subdir('test_data/scf_variation_seq');

{
    note( 'Test SCFVariationSeq generated the expected sequence file for given scf input' );

    # setup multiple matches scf and fasta files to test against
    for my $test ( 1..4 ) {
        note( "Test set $test" );
        my $temp_dir = Path::Class::tempdir(CLEANUP => 1);
        my $scf_file = $data_dir->file( $test . '.scf' )->absolute;

        ok my $qc = HTGT::QC::Util::SCFVariationSeq->new(
            species       => 'Mouse',
            target_start  => 139236822,
            target_end    => 139237728,
            target_strand => -1,
            target_chr    => 1,
            scf_file      =>  $scf_file,
            base_dir      => $temp_dir->absolute,
        ), "Constructor succeeds";

        isa_ok $qc, 'HTGT::QC::Util::SCFVariationSeq', "Object is of correct type: ";

        lives_ok {
            $qc->get_seq_from_scf
        } 'can call get_seq_from_scf';

        my $generated_seq_file = $qc->variant_seq_file;
        my $expected_seq_file  = $data_dir->file( $test . '.fa' );

        ok compare( $generated_seq_file->openr, $expected_seq_file->openr ) == 0,
            'the generated sequence file is the same as the expected sequence file';
    }

}

done_testing;
