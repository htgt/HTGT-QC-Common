#!/usr/bin/env perl
use strict;
use warnings FATAL => 'all';

=head1 NAME

10-htgt-qc-util-generate-primers

=head1 DESCRIPTION

Black box testing of HTGT::QC::Util::GeneratePrimers

=cut

use Test::Most;
use Path::Class;
use FindBin;
use Log::Log4perl ':levels';
use YAML::Any qw( LoadFile Dump );
use Bio::Seq;

Log::Log4perl->easy_init( $ERROR );

use_ok 'HTGT::QC::Util::GeneratePrimers';

my $base_data_dir = dir($FindBin::Bin)->absolute->subdir('test_data/generate_primers');
my $primer3_config_file = $base_data_dir->file( 'test_primer3_config.yaml' );

{

    for my $test ( 1..5 ) {
        my $temp_dir = Path::Class::tempdir(CLEANUP => 1);
        my $params   = LoadFile( $base_data_dir->file( $test . '.yaml' )->absolute );

        note( "Test set: " . $params->{test_name} );
        my $bio_seq  = Bio::Seq->new( -display_id => 'primer_search_region', -seq => $params->{seq} );

        my %generate_primers_params = (
            dir                       => $temp_dir,
            bio_seq                   => $bio_seq,
            region_start              => $params->{region_start},
            region_end                => $params->{region_end},
            species                   => $params->{species},
            strand                    => $params->{strand},
            primer3_config_file       => $primer3_config_file,
            primer3_target_string     => $params->{primer3_target_string},
            primer_product_size_range => $params->{product_size_string},
            check_genomic_specificity => $params->{check_genomic_specificity},
            num_genomic_hits          => $params->{num_genomic_hits},
        );

        ok my $o = HTGT::QC::Util::GeneratePrimers->new(%generate_primers_params),
            'can create GeneratePrimers object';
        isa_ok $o, 'HTGT::QC::Util::GeneratePrimers', "Object is of correct type: ";

        my $primer_pair_data;
        lives_ok{
            $primer_pair_data = $o->generate_primers
        } 'can call generate_primers';

        is $o->have_oligo_pairs, $params->{num_pairs}, 'we have expected amount of primer pairs from Primer3';

        if ( $primer_pair_data ) {
            is scalar( @{$primer_pair_data} ), $params->{num_valid_pairs},
                'we get expected amount of valid pairs';
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
