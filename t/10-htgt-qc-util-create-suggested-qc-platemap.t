#!/usr/bin/env perl

use strict;
use warnings FATAL => 'all';

use Test::Most;
use HTGT::QC::Util::CreateSuggestedQcPlateMap qw( create_suggested_plate_map );
use Log::Log4perl ':levels';

Log::Log4perl->easy_init( $DEBUG );

my @TEST_DATA = (
    {
        testname => 'GRD0080_Y only',
        seq_projects => [ qw( GRD0080_Y ) ],
        map => { GRD0080_Y_1 => 'GRD0080_Y_1' },
    },

    {
        testname => 'GRD0080_Y and GRD0080_Z',
        seq_projects => [ qw( GRD0080_Y GRD0080_Z ) ],
        map => { GRD0080_Y_1 => 'GRD0080_A', GRD0080_Z_1 => 'GRD0080_A' },
    },

    {
        testname => 'GRD0081_W and GRD0081_X',
        seq_projects => [ qw( GRD0081_W GRD0081_X ) ],
        map => { GRD0081_W_1 => 'GRD0081_C', GRD0081_X_1 => 'GRD0081_C' },
    },

    {
        testname => 'PSA5002_Z',
        seq_projects => [ qw(PSA5002_Z) ],
        map => {
            PSA5002_Z_1 => 'PSA5002_Z_1',
            PSA5002_Z_2 => 'PSA5002_Z_2',
            PSA5002_Z_3 => 'PSA5002_Z_3',
            PSA5002_Z_4 => 'PSA5002_Z_4',
            PSA5002_Z_5 => 'PSA5002_Z_5',
            PSA5002_Z_6 => 'PSA5002_Z_6',
            PSA5002_Z_7 => 'PSA5002_Z_7',
        },
    },

    {
        testname => 'MOHFAS0002_A',
        seq_projects => [ qw(MOHFAS0002_A) ],
        map => {
           MOHFAS0002_A_1  => 'MOHFAS0002_A_1',
           MOHFAS0002_A_2  => 'MOHFAS0002_A_2',
        },
    },

    {
        testname => 'Path10001_Y_1 and Path10001_Y_2',
        seq_projects => [ qw(Path10001_Y_1 Path10001_Y_2) ],
        map => {
               Path10001_Y_1_1 => 'Path10001_Y_1',
               Path10001_Y_1_2 => 'Path10001_Y_1',
               Path10001_Y_1_3 => 'Path10001_Y_1',
               Path10001_Y_1_4 => 'Path10001_Y_1',
               Path10001_Y_1_5 => 'Path10001_Y_1',
               Path10001_Y_1_6 => 'Path10001_Y_1',
               Path10001_Y_1_7 => 'Path10001_Y_1',
               Path10001_Y_1_8 => 'Path10001_Y_1',
               Path10001_Y_2_1 => 'Path10001_Y_2',
               Path10001_Y_2_2 => 'Path10001_Y_2',
               Path10001_Y_2_3 => 'Path10001_Y_2',
               Path10001_Y_2_4 => 'Path10001_Y_2',
               Path10001_Y_2_5 => 'Path10001_Y_2',
               Path10001_Y_2_6 => 'Path10001_Y_2',
               Path10001_Y_2_7 => 'Path10001_Y_2',
               Path10001_Y_2_8 => 'Path10001_Y_2'
        },
    },

    {
        testname => 'Path10001_Y_1',
        seq_projects => [ qw(Path10001_Y_1) ],
        map => {
               Path10001_Y_1_1 => 'Path10001_Y_1_1',
               Path10001_Y_1_2 => 'Path10001_Y_1_2',
               Path10001_Y_1_3 => 'Path10001_Y_1_3',
               Path10001_Y_1_4 => 'Path10001_Y_1_4',
               Path10001_Y_1_5 => 'Path10001_Y_1_5',
               Path10001_Y_1_6 => 'Path10001_Y_1_6',
               Path10001_Y_1_7 => 'Path10001_Y_1_7',
               Path10001_Y_1_8 => 'Path10001_Y_1_8',
        },
    },

    {
        testname => 'PSA5002_Z and PSA5002_Z_1 do not return suggested plate names',
        seq_projects => [ qw( PSA5002_Z PSA5002_Z_1) ],
        map => {
               PSA5002_Z_1 => '',
               PSA5002_Z_1_1 => '',
               PSA5002_Z_2 => '',
               PSA5002_Z_3 => '',
               PSA5002_Z_4 => '',
               PSA5002_Z_5 => '',
               PSA5002_Z_6 => '',
               PSA5002_Z_7 => ''
        },
    },

    {
        testname => 'MOHFAS0002_A and MOHFAS0002_A_1 do not return suggested plate names',
        seq_projects => [ qw( MOHFAS0002_A MOHFAS0002_A_1) ],
        map => {
             MOHFAS0002_A_1 => '',
             MOHFAS0002_A_1_1 => '',
             MOHFAS0002_A_2 => ''
        },
    },

);

my @TEST_FAIL = (
    {
        testname => 'invalid seq project name',
        seq_projects => [ qw( TEST ) ],
        fail_regex => qr/Unable to find sequencing project plate names for: TEST/,
    },
);

my $how_many = @TEST_DATA + @TEST_FAIL;

SKIP: {

    eval { require HTGT::DBFactory };

    skip "HTGT::DBFactory not installed", $how_many if $@;

    my $schema = HTGT::DBFactory->connect('eucomm_vector');

{
    foreach my $t ( @TEST_DATA ) {
        ok my $plate_map = create_suggested_plate_map( $t->{seq_projects}, $schema, 'Plate' ), 'call ok for ' . $t->{testname};
        is_deeply $plate_map, $t->{map} , 'expected plate map for ' . $t->{testname};
    }
}

{
    foreach my $t ( @TEST_FAIL ) {
        throws_ok { create_suggested_plate_map( $t->{seq_projects}, $schema, 'Plate' ) } $t->{fail_regex}, $t->{testname};
    }
}

}

done_testing();
