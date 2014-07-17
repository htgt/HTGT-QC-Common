#!/usr/bin/env perl
use strict;
use warnings FATAL => 'all';

=head1 NAME

10-htgt-qc-util-draw-pileup-alignment

=head1 DESCRIPTION

Black box testing of HTGT::QC::Util::DrawPileupAlignment
checking the pileup file plus parameters produces the expected aligned sequence.

=cut

use Test::Most;
use Path::Class;
use FindBin;
use File::Compare;
use Log::Log4perl ':levels';
use YAML::Any qw( LoadFile );

Log::Log4perl->easy_init( $WARN );

use_ok 'HTGT::QC::Util::DrawPileupAlignment';

my $data_dir = dir($FindBin::Bin)->absolute->subdir('test_data/draw_pileup_alignment');

{
    note( 'Testing creation of alignment strings from pileup files' );

    for my $test ( 1..7 ) {
        note( "Test set $test" );
        my $temp_dir = Path::Class::tempdir(CLEANUP => 1);
        my $pileup_file = $data_dir->file( $test . '.pileup' )->absolute;
        my $params = LoadFile( $data_dir->file( $test . '_params.yaml' )->absolute );
        my $alignments = LoadFile( $data_dir->file( $test . '_align.yaml' )->absolute );

        my $pileup_parser = HTGT::QC::Util::DrawPileupAlignment->new(
            pileup_file  => $pileup_file,
            target_start => $params->{start},
            target_end   => $params->{end},
            target_chr   => $params->{chr},
            dir          => $temp_dir,
            species      => $params->{species},
        );
        isa_ok $pileup_parser, 'HTGT::QC::Util::DrawPileupAlignment', "Object is of correct type: ";

        lives_ok{ 
            $pileup_parser->calculate_pileup_alignment
        } 'can call calculate_pileup_alignment';

        for my $seq_type ( qw( ref forward reverse ) ) {
            is $pileup_parser->seqs->{$seq_type}, $alignments->{$seq_type},
                "The $seq_type sequence is correct";
        }
    }

}

done_testing;
