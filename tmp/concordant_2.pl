#!/usr/bin/env perl
use strict;
use warnings FATAL => 'all';

use List::Util qw( min );
use Smart::Comments;

my @test_data = (
    #{
        #string_a =>  'MMMMMDMMMMMMMMMMMMMMMMMMMMMDDMDDMMDDDDDDDMMDMMMMDDMDDDDDDDDDDDDDDDDDDDDMMMMMDMDMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMM',
        #string_b => 'MMMMMMMMDMMMMMMMMMMMMMMMMMMDDMDDMMDDDDDDDMMDMMMMDDMDDDDDDDDDDDDDDDDDDDDMMMMMDMDMMMMMMMMMMMMMMMMMMMMMMMMMMM',
    #},
    #{
        #string_a => 'MMMMMMMMMMMDDDDDDDDMMMMMMMMM',
        #string_b => 'MMMMMMMMMMDMDDDDDDDMMMMMMMMM',
    #},
    #{
        #string_a => 'MMMMMMMMMMDMDDDDDDDMMMMMMMMM',
        #string_b => 'MMMMMMMMMMMDDDDDDDDMMMMMMMMM',
    #},
    #{
        #string_a => 'MMMMMMMMDDDDDDDDMMMMMMM',
        #string_b => 'XXXXXMMMMMMMMMMMMDDDMMM',
    #},
    #{
        #string_a => 'MMMMMMMMMMDDDDDDDDMMMMMMMMMMMM',
        #string_b => 'MMMMMMMMMMDDDDDDDDDDDMMMMMMMMM',
    #},
    #{
        #string_a => 'MMMMMMMMMMDDDDDDDDDDDMMMMMMMMM',
        #string_b => 'MMMMMMMMMMDDDDDDDDMMMMMMMMMMMM',
    #},
    #{
        #string_a => 'MMMMMMMMMMDDDDDDDDMMMMMMMMMMMMMMMMMMMMMMDDDDDDDDMMMMMMMMMMMM',
        #string_b => 'MMMMMMMMMMDDDDDDDDMMMMMMMMMMMMMMMMMMMMMMDDDDDDDDMMMMMMMMMMMM',
    #},
    #{
        #string_a => 'MMMMMMMMMMDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDMMMMMMMMMMMM',
        #string_b => 'MMMMMMMMMMDDDDDDDDMMMMDDDDDDDDDDDDDDMMMMDDDDDDDDMMMMMMMMMMMM',
    #},
    #{
        #string_a => 'MMMMMMMMMMDDDDDDDDMMMMDDDDDDDDDDDDDDMMMMDDDDDDDDMMMMMMMMMMMM',
        #string_b => 'MMMMMMMMMMDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDMMMMMMMMMMMM',
    #},
    {
        string_a => 'MMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDMMMMMMMM',
        string_b => 'MMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDMMMMMMMM',
    },
    {
        string_a => 'MMMMMMMMMMDDDDMM',
        string_b => 'MMMMMMMMMMDDDDMM',
    },
);

for my $test ( @test_data ) {
    my $result = concordant_cigar_deletions( $test->{string_a}, $test->{string_b} );
    ### $result
}

sub concordant_cigar_deletions {
    my ( $string_a, $string_b ) = @_;

    my $string_length = min( length( $string_a ), length( $string_b ) );

    my @a = split( //, $string_a );
    my @b = split( //, $string_b );

    my $current_max_length = 0;
    my @concordant_positions;

    my $d_run = 0;
    my $d_run_pos;
    my $d_run_len;
    for ( my $i = 0; $i < $string_length; $i++ ) {
        my $a_char = $a[$i];
        my $b_char = $b[$i];

        if ( $a_char eq 'D' && $b_char eq 'D' ) {
            if ( $d_run ) {
                $d_run_len++;
            }
            else {
                $d_run = 1;
                $d_run_pos = $i;
                $d_run_len = 1;
            }
        }
        else {
            if ( $d_run ) {
                if ( $d_run_len > $current_max_length ) {
                    $current_max_length = $d_run_len;
                    @concordant_positions = $d_run_pos; 
                }
                elsif ( $d_run_len == $current_max_length ) {
                    push @concordant_positions, $d_run_pos;
                }
                $d_run = 0;
                $d_run_pos = undef;
                $d_run_len = undef;
            }
        }
    }

    return { $current_max_length => \@concordant_positions };
} 
