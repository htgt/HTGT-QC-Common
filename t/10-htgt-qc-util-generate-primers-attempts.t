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

    for my $test ( 1..4 ) {
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
        );
        $primer_params{product_size_avoid} = $params->{product_size_avoid}
            if exists $params->{product_size_avoid};

        $primer_params{forward_primer} = $params->{forward_primer}
            if exists $params->{forward_primer};

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

            if ( $params->{valid_primers} ) {
                is_deeply $primer_pair_data, $params->{valid_primers}, 'we get expected primer pairs';
            }
        }
        else {
            ok $params->{no_valid_primers}, 'no valid primers produced';
        }

    }

}

done_testing;
