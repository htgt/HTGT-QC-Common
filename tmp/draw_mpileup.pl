#!/usr/bin/env perl
use strict;
use warnings FATAL => 'all';

use feature qw( say );
use HTGT::QC::Util::DrawPileupAlignment;

my $pileup_parser = HTGT::QC::Util::DrawPileupAlignment->new(
    pileup_file => $ARGV[0],
    target_start => 203678601,
    target_end   => 203678646,
    target_chr   => 1,
);

$pileup_parser->calculate_pileup_alignment;
my $seqs = $pileup_parser->seqs;

my @keys = keys %{ $seqs };
my $length = length( $seqs->{ref} );
my $start = 0;
while ( $start < $length  ) {
    for my $name ( @keys ) {
        say substr($name, 0,3 ) . ": " . substr( $seqs->{$name}, $start, 230 );
    }
    say '---';
    $start += 230;
}

#say 'G: ' . $seqs->{ref_trunc};
#say 'F: ' . $seqs->{forward_trunc};
#say 'R: ' . $seqs->{reverse_trunc};
