#!/usr/bin/env perl

use strict;
use warnings FATAL => 'all';

use Test::Most;
use Path::Class;
use Bio::Seq;
use Log::Log4perl ':levels';

Log::Log4perl->easy_init( $DEBUG );

use_ok 'HTGT::QC::Util::CrisprAlleleDamage';

my @CONCORDANT_DELETION_TEST_DATA = (
    {
        forward_cigar   => 'MMDMMMMMMMMMMMMMMMMMMMMMDDMDDMMDDDDDDDMMDMMMMDDMDDDDDDDDDDDDMMMMD',
        reverse_cigar   => 'MMMMMDMMMMMMMMMMMMMMMMMMDDMDDMMDDDDDDDMMDMMMMDDMDDDDDDDDDDDDM',
        expected_result => { length => 12, positions => [ 48 ] },
    },
    {
        forward_cigar   => 'MMMMMMMMMMMDDDDDDDDMMMMMMMMM',
        reverse_cigar   => 'MMMMMMMMMMDMDDDDDDDMMMMMMMMM',
        expected_result => { length => 7, positions => [ 12 ] },
    },
    {
        forward_cigar   => 'MMMMMMMMMMDMDDDDDDDMMMMMMMMM',
        reverse_cigar   => 'MMMMMMMMMMMDDDDDDDDMMMMMMMMM',
        expected_result => { length => 7, positions => [ 12 ] },
    },
    {
        forward_cigar   => 'MMMMMMMMDDDDDDDDMMMMMMM',
        reverse_cigar   => 'XXXXXMMMMMMMMMMMMDDDMMM',
        expected_result => undef,
    },
    {
        forward_cigar => 'MMMMMMMMMMDDDDDDDDMMMMMMMMMMMM',
        reverse_cigar => 'MMMMMMMMMMDDDDDDDDDDDMMMMMMMMM',
        expected_result => { length => 8, positions => [ 10 ] },
    },
    {
        forward_cigar => 'MMMMMMMMMMDDDDDDDDDDDMMMMMMMMM',
        reverse_cigar => 'MMMMMMMMMMDDDDDDDDMMMMMMMMMMMM',
        expected_result => { length => 8, positions => [ 10 ] },
    },
    {
        forward_cigar => 'MMMMMMMMMMDDDDDDDDMMMMMMMMMMMMMMMMMMMMMMDDDDDDDDMMMMMMMMMMMM',
        reverse_cigar => 'MMMMMMMMMMDDDDDDDDMMMMMMMMMMMMMMMMMMMMMMDDDDDDDDMMMMMMMMMMMM',
        expected_result => { length => 8, positions => [ 10, 40 ] },
    },
    {
        forward_cigar => 'MMMMMMMMMMDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDMMMMMMMMMMMM',
        reverse_cigar => 'MMMMMMMMMMDDDDDDDDMMMMDDDDDDDDDDDDDDMMMMDDDDDDDDMMMMMMMMMMMM',
        expected_result => { length => 14, positions => [ 22 ] },
    },
    {
        forward_cigar => 'MMMMMMMMMMDDDDDDDDMMMMDDDDDDDDDDDDDDMMMMDDDDDDDDMMMMMMMMMMMM',
        reverse_cigar => 'MMMMMMMMMMDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDMMMMMMMMMMMM',
        expected_result => { length => 14, positions => [ 22 ] },
    },
    {
        forward_cigar => 'MMMMMMMMMMDDDDMM',
        reverse_cigar => 'MMMMMMMMMMDDDDMM',
        expected_result => { length => 4, positions => [ 10 ] },
    },
);

{
    note( 'Test concordant deletion' );

    my $temp_dir = Path::Class::tempdir(CLEANUP => 1);
    ok my $qc = HTGT::QC::Util::CrisprAlleleDamage->new(
        genomic_region         => Bio::Seq->new( -id => 'test', -seq => 'ATCG' ),
        forward_primer_read    => Bio::Seq->new( -id => 'test', -seq => 'AT' ),
        forward_primer_name    => 'SPF',
        reverse_primer_name    => 'SPR',
        dir                    => $temp_dir->absolute,
    ), "Constructor succeeds";
    isa_ok $qc, 'HTGT::QC::Util::CrisprAlleleDamage', "Object is of correct type: ";

    for my $data ( @CONCORDANT_DELETION_TEST_DATA ) {
        my $result;
        lives_ok {
            $result
                = $qc->concordant_deletions( $data->{forward_cigar}, $data->{reverse_cigar} );
        }
        'can call concordant_deletions subroutine';
        is_deeply $result, $data->{expected_result}, 'we have the expected result';

    }

}

my @CONCORDANT_INSERTION_TEST_DATA = (
    {
        forward_cigar      => 'MQMDQMMMMMMMM',
        reverse_cigar      => 'MQMMMQMMMMMM',
        forward_insertions => { 2 => 'TTA', 5 => 'ATG' },
        reverse_insertions => { 2 => 'TTA', 6 => 'CGA' },
        expected_result    => { length => 3, positions => [ 2 ], seq => 'TTA' },
    },
    {
        forward_cigar      => 'MMQMMQM',
        reverse_cigar      => 'MMQMMQM',
        forward_insertions => { 3 => 'TTAT', 6 => 'ATG' },
        reverse_insertions => { 3 => 'TTAA', 6 => 'ATG' },
        expected_result    => { length => 3, positions => [ 6 ], seq => 'ATG' },
    },
    {
        forward_cigar      => 'MMQMMM',
        reverse_cigar      => 'MMQMMM',
        forward_insertions => { 3 => 'TTATA' },
        reverse_insertions => { 3 => 'TTATA' },
        expected_result    => { length => 5, positions => [ 3 ], seq => 'TTATA' },
    },
    {
        forward_cigar      => 'MMQMMM',
        reverse_cigar      => 'MMQMMM',
        forward_insertions => { 3 => 'GTATA' },
        reverse_insertions => { 3 => 'TTATA' },
        expected_result    => undef,
    },
);

{
    note( 'Test condordant insertion' );

    my $temp_dir = Path::Class::tempdir(CLEANUP => 1);
    ok my $qc = HTGT::QC::Util::CrisprAlleleDamage->new(
        genomic_region         => Bio::Seq->new( -id => 'test', -seq => 'ATCG' ),
        forward_primer_read    => Bio::Seq->new( -id => 'test', -seq => 'AT' ),
        forward_primer_name    => 'SPF',
        reverse_primer_name    => 'SPR',
        dir                    => $temp_dir->absolute,
    ), "Constructor succeeds";
    isa_ok $qc, 'HTGT::QC::Util::CrisprAlleleDamage', "Object is of correct type: ";

    for my $data ( @CONCORDANT_INSERTION_TEST_DATA ) {
        my $result;
        lives_ok {
            $result = $qc->concordant_insertions(
                $data->{forward_cigar},
                $data->{reverse_cigar},
                $data->{forward_insertions},
                $data->{reverse_insertions},
            );
        }
        'can call concordant_insertions subroutine';
        is_deeply $result, $data->{expected_result}, 'we have the expected result';

    }
}

note( 'NOTE: Only tested concordant_deletions and concordant_insertions subroutines' );

done_testing;
