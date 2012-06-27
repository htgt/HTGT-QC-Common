#!/usr/bin/env perl

use strict;
use warnings FATAL => 'all';

use Test::Most;
use Log::Log4perl qw( :levels );

Log::Log4perl->easy_init( $TRACE );

die_on_fail;

use_ok 'HTGT::QC::Util::CigarParser';

{    
    my $cigar_str = 'cigar: Gpc3_R1_1858289-CherryD11.w2k0 18 704 + vector_374239_ENSMUSE00000436236_Ifitm2_intron_R1_ZeoPheS_R2_R3R4_pBR_amp 9478 8792 - 3268  M 686 I 17 M 32';

    ok my $cigar = HTGT::QC::Util::CigarParser->new(strict_mode=>0)->parse_cigar( $cigar_str ), 'parse_cigar succeeds';

    is_deeply $cigar, {
        query_id      => 'Gpc3_R1_1858289-CherryD11.w2k0',
        query_well    => 'Gpc3_R1_1858289-CherryD11',
        query_primer  => '',
        query_start   => 18,
        query_end     => 704,
        query_strand  => '+',
        target_id     => 'vector_374239_ENSMUSE00000436236_Ifitm2_intron_R1_ZeoPheS_R2_R3R4_pBR_amp',
        target_start  => 9478,
        target_end    => 8792,
        target_strand => '-',
        score         => 3268,
        op_str        => "M 686 I 17 M 32",
        operations    => [ [ M => 686 ], [ I => 17 ], [ M => 32 ] ],
        length        => 686,
        raw           => $cigar_str,
    }, 'parse_cigar returns the expected data structure';
}

{
    my $cigar_str = 'cigar: EPD00921_1_A_1a04.p1kaR2R 0 363 + 382262#Ifitm2_intron_L1L2_GTK_LacZ_BetactP_neo 21588 21954 + 1778  M 21 D 1 M 129 D 2 M 213';

    ok my $cigar = HTGT::QC::Util::CigarParser->new(primers=>['R2R'])->parse_cigar( $cigar_str ), 'parse_cigar succeeds';

    is_deeply $cigar, {
        length        => 366,
        op_str        => "M 21 D 1 M 129 D 2 M 213",
        operations    => [["M", 21], ["D", 1], ["M", 129], ["D", 2], ["M", 213]],
        query_end     => 363,
        query_id      => "EPD00921_1_A_1a04.p1kaR2R",
        query_primer  => "R2R",
        query_start   => 0,
        query_strand  => "+",
        query_well    => "EPD00921_1_A_1A04",
        raw           => "cigar: EPD00921_1_A_1a04.p1kaR2R 0 363 + 382262#Ifitm2_intron_L1L2_GTK_LacZ_BetactP_neo 21588 21954 + 1778  M 21 D 1 M 129 D 2 M 213",
        score         => 1778,
        target_end    => 21954,
        target_id     => "382262#Ifitm2_intron_L1L2_GTK_LacZ_BetactP_neo",
        target_start  => 21588,
        target_strand => "+",
    }, 'parse_cigar returns the expected data structure';    
}

done_testing;
