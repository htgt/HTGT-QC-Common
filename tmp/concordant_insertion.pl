#!/usr/bin/env perl
use strict;
use warnings FATAL => 'all';

use List::Util qw( min );
use Smart::Comments;

my @test_data = (
    {
        string_a => 'MQMDQMMMMMMMM',
        string_b => 'MQMMMQMMMMMM',
        insertions_a => { 1 => 'TTA', 4 => 'ATG' },
        insertions_b => { 1 => 'TTA', 5 => 'CGA' },
    },
    {
        string_a => 'MMQMMQM',
        string_b => 'MMQMMQM',
        insertions_a => { 2 => 'TTAT', 5 => 'ATG' },
        insertions_b => { 2 => 'TTAA', 5 => 'ATG' },
    },
    {
        string_a => 'MMQMMM',
        string_b => 'MMQMMM',
        insertions_a => { 2 => 'TTATA' },
        insertions_b => { 2 => 'TTATA' },
    },
    {
        string_a => 'MMQMMM',
        string_b => 'MMQMMM',
        insertions_a => { 2 => 'GTATA' },
        insertions_b => { 2 => 'TTATA' },
    },
);

for my $test ( @test_data ) {
    my $result = concordant_cigar_insertions(
        $test->{string_a},
        $test->{string_b},
        $test->{insertions_a},
        $test->{insertions_b},
    );
    ### $result
}

sub concordant_cigar_insertions {
    my ( $forward_cigar, $reverse_cigar, $forward_insertions, $reverse_insertions ) = @_;

    my $forward_ins_positions = insertion_data( $forward_cigar );
    my $reverse_ins_positions = insertion_data( $reverse_cigar );

    my $current_max_length = 0;
    my @concordant_positions;

    for my $forward_pos ( keys %{ $forward_ins_positions } ) {
        next unless exists $reverse_ins_positions->{$forward_pos};

        # insertion on same place in both cigars, now check if sequence the same
        my $forward_ins_seq = $forward_insertions->{$forward_pos};
        my $reverse_ins_seq = $reverse_insertions->{$forward_pos};

        if ( $reverse_ins_seq && $forward_ins_seq && $reverse_ins_seq eq $forward_ins_seq ) {
            my $ins_length = length( $forward_ins_seq );
            if ( $ins_length > $current_max_length ) {
                $current_max_length = $ins_length;
                @concordant_positions = ( $forward_pos );
            }
            elsif ( $ins_length == $current_max_length ) {
                push @concordant_positions, $forward_pos;
            }
        }
    }

    return { $current_max_length => \@concordant_positions };
}

sub insertion_data {
    my $string = shift;

    my %data;
    while ($string =~ /Q/g) {
        my $start = $-[0];
        $data{$start} = undef;
    }

    return \%data;
}
