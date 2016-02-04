#!/usr/bin/env perl
use strict;
use warnings FATAL => 'all';

=head1 NAME

10-htgt-qc-util-generate-primers-attempts

=head1 DESCRIPTION

Black box testing of HTGT::QC::Util::GeneratePrimersAttempts

=cut

use Test::Most;
use Path::Class;
use FindBin;
use Log::Log4perl ':levels';
use YAML::Any qw( LoadFile );

Log::Log4perl->easy_init( $ERROR );

use_ok 'HTGT::QC::Util::GeneratePrimersAttempts';

my $base_data_dir = dir($FindBin::Bin)->absolute->subdir('test_data/generate_primers_attempts');
my $primer3_config_file = $base_data_dir->file( 'test_primer3_config.yaml' );

{

    for my $test ( 1..8 ) {
        my $temp_dir = Path::Class::tempdir(CLEANUP => 1);
        my $params   = LoadFile( $base_data_dir->file( $test . '.yaml' )->absolute );

        note( "Test set: " . $params->{test_name} );

        my %primer_params = (
            base_dir                  => $temp_dir,
            primer3_config_file       => $primer3_config_file,
            species                   => $params->{species},
            strand                    => $params->{strand},
            chromosome                => $params->{chromosome},
            target_start              => $params->{target_start},
            target_end                => $params->{target_end},
            five_prime_region_size    => $params->{five_prime_region_size},
            five_prime_region_offset  => $params->{five_prime_region_offset},
            three_prime_region_size   => $params->{three_prime_region_size},
            three_prime_region_offset => $params->{three_prime_region_offset},
            primer3_task              => $params->{primer3_task} || 'pick_pcr_primers',
        );

        for my $name ( qw( produce_size_avoid forward_primer excluded_regions included_regions ) ) {
            $primer_params{$name} = $params->{$name}
                if exists $params->{$name};
        }

        ok my $o = HTGT::QC::Util::GeneratePrimersAttempts->new( %primer_params ),
            'can create GeneratePrimersAttempts object';
        isa_ok $o, 'HTGT::QC::Util::GeneratePrimersAttempts', "Object is of correct type: ";

        my ( $primer_pair_data, $seq );
        lives_ok{
            ( $primer_pair_data, $seq ) = $o->find_primers;
        } 'can call find_primers';

        if ( $primer_pair_data ) {
            is scalar( @{$primer_pair_data} ), $params->{num_valid_pairs},
                'we get expected amount of valid pairs';
            is $params->{expected_attempt_number}, $o->current_attempt, 'expected attempt number';
            is_deeply $params->{expected_product_size_array}, $o->product_size_array,
                'expected product size array';

            additional_tests( $params, $primer_pair_data );

            if ( $params->{valid_primers} ) {
                is_deeply $primer_pair_data, $params->{valid_primers}, 'we get expected primer pairs';
            }
        }
        else {
            ok $params->{no_valid_primers}, 'no valid primers produced';
        }

    }

}

sub additional_tests {
    my ( $params, $primer_pairs ) = @_;

    # tests for sequence_excluded_region, none of the primers must be within
    # the excluded region.
    if ( exists $params->{excluded_regions} ) {
        for my $oligo_pair ( @{ $primer_pairs } ) {
            ok !(  $oligo_pair->{forward}{oligo_start} > $params->{excluded_regions}[0]{start}
                && $oligo_pair->{forward}{oligo_start} < $params->{excluded_regions}[0]{end} ),
                'forward oligo is not within excluded region';
        }
    }

    # tests for sequence_included_region, all of the primers must be within
    # the included region.
    if ( exists $params->{included_regions} ) {
        for my $oligo_pair ( @{ $primer_pairs } ) {
            ok $oligo_pair->{forward}{oligo_start} >= $params->{included_regions}[0]{start}
                && $oligo_pair->{forward}{oligo_start} <= $params->{included_regions}[0]{end},
                'forward oligo is within included region';
        }
    }

    # pick_left_only task, we should only have left ( forward ) primers
    if ( exists $params->{primer3_task} && $params->{primer3_task} eq 'pick_left_only' ) {
        for my $oligo_pair ( @{ $primer_pairs } ) {
            ok exists $oligo_pair->{forward}, 'we have a left / forward primer';
            ok !exists $oligo_pair->{reverse}, 'we do not have a right / reverse primer';
        }
    }

    # pick_right_only task, we should only have  right ( reverse ) primers
    if ( exists $params->{primer3_task} && $params->{primer3_task} eq 'pick_right_only' ) {
        for my $oligo_pair ( @{ $primer_pairs } ) {
            ok exists $oligo_pair->{reverse}, 'we have a right / reverse primer';
            ok !exists $oligo_pair->{forward}, 'we do not have a left / forward primer';
        }
    }
}

done_testing;
