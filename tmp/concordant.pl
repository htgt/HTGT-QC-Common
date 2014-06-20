#!/usr/bin/env perl
use strict;
use warnings FATAL => 'all';

use List::Util qw( min );
use Smart::Comments;

my @test_data = (
    {
        string_a =>  'MMMMMDMMMMMMMMMMMMMMMMMMMMMDDMDDMMDDDDDDDMMDMMMMDDMDDDDDDDDDDDDDDDDDDDDMMMMMDMDMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMM',
        string_b => 'MMMMMMMMDMMMMMMMMMMMMMMMMMMDDMDDMMDDDDDDDMMDMMMMDDMDDDDDDDDDDDDDDDDDDDDMMMMMDMDMMMMMMMMMMMMMMMMMMMMMMMMMMM',
    },
    {
        string_a => 'MMMMMMMMMMMDDDDDDDDMMMMMMMMM',
        string_b => 'MMMMMMMMMMDMDDDDDDDMMMMMMMMM',
    },
    {
        string_a => 'MMMMMMMMMMDMDDDDDDDMMMMMMMMM',
        string_b => 'MMMMMMMMMMMDDDDDDDDMMMMMMMMM',
    },
    {
        string_a => 'MMMMMMMMDDDDDDDDMMMMMMM',
        string_b => 'XXXXXMMMMMMMMMMMMDDDMMM',
    },
    {
        string_a => 'MMMMMMMMMMDDDDDDDDMMMMMMMMMMMM',
        string_b => 'MMMMMMMMMMDDDDDDDDDDDMMMMMMMMM',
    },
    {
        string_a => 'MMMMMMMMMMDDDDDDDDDDDMMMMMMMMM',
        string_b => 'MMMMMMMMMMDDDDDDDDMMMMMMMMMMMM',
    },
    {
        string_a => 'MMMMMMMMMMDDDDDDDDMMMMMMMMMMMMMMMMMMMMMMDDDDDDDDMMMMMMMMMMMM',
        string_b => 'MMMMMMMMMMDDDDDDDDMMMMMMMMMMMMMMMMMMMMMMDDDDDDDDMMMMMMMMMMMM',
    },
    {
        string_a => 'MMMMMMMMMMDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDMMMMMMMMMMMM',
        string_b => 'MMMMMMMMMMDDDDDDDDMMMMDDDDDDDDDDDDDDMMMMDDDDDDDDMMMMMMMMMMMM',
    },
    {
        string_a => 'MMMMMMMMMMDDDDDDDDMMMMDDDDDDDDDDDDDDMMMMDDDDDDDDMMMMMMMMMMMM',
        string_b => 'MMMMMMMMMMDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDMMMMMMMMMMMM',
    },
);

for ( 1..100 ) {
    for my $test ( @test_data ) {
        my $result = concordant_cigar_deletions( $test->{string_a}, $test->{string_b} );
    }
}

sub concordant_cigar_deletions {
    my ( $string_a, $string_b ) = @_;

    my $a_data = deletion_data( $string_a );

    my $current_max_length = 0;
    my @concordant_positions;
    for my $a_position ( sort { $a <=> $b } keys %{ $a_data } ) {
        my $a_length = $a_data->{$a_position};
        next if $a_length < $current_max_length;

        # grab matching substr from string b
        my $b_sub_string = substr( $string_b, $a_position, $a_length );
        my $b_data = deletion_data( $b_sub_string );

        if ( %{ $b_data } ) {
            for my $b_position ( sort { $a <=> $b } keys %{ $b_data } ) {
                my $b_length = $b_data->{$b_position};
                next if $b_length < $current_max_length;

                my $position = $a_position + $b_position;
                if ( $b_length > $current_max_length ) {
                    @concordant_positions = $position; 
                    $current_max_length = $b_length;
                }
                elsif ( $b_length == $current_max_length ) {
                    push @concordant_positions, $position;
                }

            }
        }
    }

    return { $current_max_length => \@concordant_positions };
}

sub deletion_data {
    my $string = shift;

    my %data;
    while ($string =~ /(D+)/g) {
        my $start = $-[1];
        my $length = length($1);
        $data{$start} = $length;
    }

    return \%data;
}
