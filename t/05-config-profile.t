#!/usr/bin/env perl

use strict;
use warnings FATAL => 'all';

use Test::Most;

use_ok 'HTGT::QC::Config::Profile';

{
    ok my $p = HTGT::QC::Config::Profile->new(
        vector_stage         => 'final',
        profile_name         => 'test profile',
        alignment_regions    => { A => 1, B => 1, C => 1 },
        pre_filter_min_score => 1000,
        pass_condition       => 'X AND Y AND Z',
        primers              => { X => 'A AND B',
                                  Y => 'A',
                                  Z => 'A AND (B OR C)'
                              },
    ), 'construct profile';

    cmp_bag $p->regions_for_primer( 'X' ), [ 'A', 'B' ], 'regions for X';
    cmp_bag $p->regions_for_primer( 'Y' ), [ 'A' ], 'regions for Y';
    cmp_bag $p->regions_for_primer( 'Z' ), [ 'A', 'B', 'C' ], 'regions for Z';

    is $p->pass_condition, 'X AND Y AND Z', 'pass_condition';
    is $p->pre_filter_min_score, 1000, 'pre_filter_score';

    my %results = ( A => { pass => 1 }, C => { pass => 1 } );    
    ok !$p->is_primer_pass( 'X', \%results ), 'primer X fail';
    ok $p->is_primer_pass( 'Y', \%results ), 'primer Y pass';
    ok $p->is_primer_pass( 'Z', \%results ), 'primer Z pass';

    ok $p->is_pass( { X => { pass => 1 }, Y => { pass => 1 }, Z => { pass => 1 } } ), 'passing condition';
    ok !$p->is_pass( { X => { pass => 1 }, Y => { pass => 0 }, Z => { pass => 1 } } ), 'failing condition';
    
}

throws_ok {
    HTGT::QC::Config::Profile->new(
        vector_stage          => 'final',
        profile_name          => 'test profile',
        alignment_regions     => { A => 1, B => 1 },
        pre_filter_min_score  => 1000,
        pass_condition        => 'X AND Y AND Z',
        primers               => { X => 'A AND B',
                                   Y => 'A',
                                   Z => 'A AND (B OR C)'
                               },
    );        
} qr/\QAlignment region 'C' for primer 'Z' is not defined\E/, 'throws exception when primer condititon references undefined region';

throws_ok {
    HTGT::QC::Config::Profile->new(
        vector_stage          => 'final',
        profile_name          => 'test profile',
        alignment_regions     => { A => 1, B => 1, C => 1 },
        pre_filter_min_score  => 1000,
        pass_condition        => 'X AND Y AND Z',
        primers               => { X => 'A AND B',
                                   Y => '',
                                   Z => 'A AND (B OR C)'
                               },
    );    
} qr/\QNo regions defined for primer 'Y'\E/, 'throws exception when no regions are defined for a primer';
   
throws_ok {
    HTGT::QC::Config::Profile->new(
        vector_stage          => 'final',
        profile_name          => 'test profile',
        alignment_regions     => { A => 1, B => 1, C => 1 },
        pre_filter_min_scroe  => 1000,
        pass_condition        => 'X AND Y AND Z',
        primers               => { X => 'A AND B',
                                   Y => 'A',
                                   Z => 'A AND (B OR C)'
                               },
    );    
} qr/\QFound unknown attribute(s) passed to the constructor\E/, 'throws exception when attribute name is mistyped';

done_testing;
