package HTGT::QC::Util::AnalyzeAlignment;

use strict;
use warnings FATAL => 'all';

use Sub::Exporter -setup => {
    exports => [ 'analyze_alignment' ],
    groups => {
        default => [ 'analyze_alignment' ]
    }
};

use HTGT::QC::Util::FindSeqFeature qw();
use HTGT::QC::Util::Alignment qw( alignment_match );
use Log::Log4perl qw( :easy );
use List::MoreUtils qw( all );
use Data::Dump qw( pp );

sub analyze_alignment {
    my ( $target, $query, $cigar, $profile ) = @_;

    my $primer = $cigar->{query_primer}
        or die "failed to parse primer name from cigar: '$cigar->{raw}'";

    DEBUG( "analyze_alignment; target: " . $target->display_id
               . ", query: " . $query->display_id
                   . ", primer: " . $primer );

    my %result = (
        primer   => $primer,
        cigar    => $cigar,
        features => overlapping_features( $target, $cigar )
    );

    for my $region_name ( @{ $profile->regions_for_primer( $primer ) } ) {
        DEBUG( "Analyzing region $region_name" );
        my $region = $profile->alignment_region( $region_name );
        if ( $cigar->{target_strand} ne $region->{expected_strand} ) {
            INFO( "Strand mismatch" );
            $result{pass} = 0;
            #last;
        }
        my $start = get_target_pos( $target, %{ $region->{start} } );
        my $end   = get_target_pos( $target, %{ $region->{end} } );
        DEBUG "Target region coords: $start to $end";
        my $critical_region_length = abs( $start - $end ) + 1;
        my $alignment = alignment_match( $query, $target, $cigar, $start, $end );
        if ( $region->{min_match_pct} ) {
            $alignment->{pass} = $alignment->{match_pct} >= $region->{min_match_pct};
        }
        elsif ( $region->{min_match_length} ) {
            $alignment->{pass} = check_alignment_pass( $region->{min_match_length}, $alignment );
        }
        elsif ( $region->{ensure_no_indel} ) {
                $alignment->{pass} = ensure_no_indel( $alignment );
            }
        else {
            ERROR( "No pass criteria defined for primer $primer region $region_name" );
        }

        INFO( sprintf 'Primer %s, target %s, %d%%', $primer, $region_name, $alignment->{match_pct} );
        $result{alignment}{$region_name} = $alignment;
    }

    $result{pass} = $profile->is_primer_pass( $primer, $result{alignment} );
    INFO( "Primer $primer: " . ( $result{pass} ? 'pass' : 'fail' ) );

    return \%result;
}

sub ensure_no_indel {
    my $alignment = shift;

    DEBUG( "ensure_no_indel" );

    for my $key ( qw( target_str query_str ) ) {
        my $seq_str = $alignment->{$key};
        if ( $seq_str =~ m/-/ ) {
            WARN( "Indel detected in $key '$seq_str'" );
            return 0;
        }
    }

    DEBUG( "ensure_no_indel returning success" );
    return 1;
}

sub check_alignment_pass {
    my ( $condition, $alignment ) = @_;

    DEBUG( "check_alignment_pass: $condition" );
    if ( my ( $length ) = $condition =~ m{^(\d+)$} ) {
        DEBUG( "Checking match_count" );
        return $alignment->{match_count} >= $length;
    }
    elsif ( my ( $num, $denom ) = $condition =~ m{^(\d+)/(\d+)$} ) {
        DEBUG( "Checking subequences for minimal match length" );
        return 0 unless $alignment->{length} >= $denom;
        my $match_str = $alignment->{match_str};
        for my $start_ix ( 0 .. ( $alignment->{length} - $denom ) ) {
            my $sub_match = substr( $match_str, $start_ix, $denom );
            my $sub_match_len = $sub_match =~ tr{|}{|};
            if ( $sub_match_len >= $num ) {
                DEBUG( "Got passing substring: $sub_match" );
                return 1;
            }
        }
        return 0;
    }
    else {
        die "Failed to parse alignment match length: '$condition'";
    }
}

sub overlapping_features {
    my ( $target, $cigar ) = @_;

    my ( $start, $end ) = @{$cigar}{ qw( target_start target_end ) };
    ( $start, $end ) = ( $end, $start ) if $start > $end;

    my @overlapping_features;

    for my $feature ( $target->get_SeqFeatures ) {
        next unless $feature->start and $feature->end;
        if ( $feature->start < $end and $feature->end > $start ) {
            push @overlapping_features, $feature;
        }
    }

    my @results;
    if ( $cigar->{target_strand} eq '+' ) {
        @results = map { feature_name( $_ ) } sort { $a->start <=> $b->start } @overlapping_features;
    }
    else {
        @results = map { feature_name( $_ ) } sort { $b->start <=> $a->start } @overlapping_features;
    }

    return \@results;
}

sub feature_name {
    my $feature = shift;

    if ( $feature->has_tag( 'note' ) ) {
        return join q{ }, $feature->get_tag_values( 'note' );
    }
    elsif ( $feature->has_tag( 'label' ) ) {
        return join q{ }, $feature->get_tag_values( 'label' );
    }
    else {
        return 'unknown';
    }
}

sub get_target_pos {
    my ( $target, %locus ) = @_;
    DEBUG( "get_target_pos: " . pp( \%locus ) );

    if ( defined( my $start_offset = delete $locus{start} ) ) {
        my $feature_loc = find_seq_feature_loc( $target, %locus );
        return $feature_loc->start + $start_offset;
    }
    elsif ( defined( my $end_offset = delete $locus{end} ) ) {
        my $feature_loc = find_seq_feature_loc( $target, %locus );
        return $feature_loc->end + $end_offset;
    }

    die "Invalid target locus (no start or end defined): " . pp( \%locus );
}

sub find_seq_feature_loc {
    my ( $target, %locus ) = @_;

    for ( values %locus ) {
        if ( ref $_ eq 'HASH' and exists $_->{match} ) {
            $_ = qr/$_->{match}/
        }
    }

    HTGT::QC::Util::FindSeqFeature::find_seq_feature_loc( $target, %locus );
}


1;

__END__

