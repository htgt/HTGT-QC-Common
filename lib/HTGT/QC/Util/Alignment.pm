package HTGT::QC::Util::Alignment;

use strict;
use warnings FATAL => 'all';

use Sub::Exporter -setup => {
    exports => [ qw( target_alignment_string
                     query_alignment_string
                     target_alignment_string_pos
                     alignment_match
                     format_alignment
               ) ],
};

use Const::Fast;
use List::Util qw( min sum );
use Log::Log4perl ':easy';
use Data::Dump 'pp';
use HTGT::QC::Exception;

const my $DISPLAY_HEADER_LEN => 12;
const my $DISPLAY_LINE_LEN   => 72;

sub target_alignment_string {
    my ( $bio_seq, $cigar ) = @_;

    my ( $seq, $target_start, $target_end );
    if ( $cigar->{target_strand} eq '-' ) {
        $seq = $bio_seq->revcom->seq;
        $target_start = $bio_seq->length - $cigar->{target_start};
        $target_end   = $bio_seq->length - $cigar->{target_end};
    }
    else {
        $seq = $bio_seq->seq;
        $target_start = $cigar->{target_start};
        $target_end   = $cigar->{target_end};
    }

    my $pos = 0;
    my $alignment_str;

    if ( $target_start > 0 ) {
        $alignment_str .= substr( $seq, 0, $target_start );
        $pos += $target_start;
    }

    for ( @{ $cigar->{operations} } ) {
        my ( $op, $length ) = @$_;
        if ( $op eq 'M' or $op eq 'D' ) {
            $alignment_str .= substr( $seq, $pos, $length );
            $pos += $length;
        }
        else { # $op eq 'I'
            $alignment_str .= '-' x $length;
        }
    }

    if ( $pos < length( $seq ) ) {
        $alignment_str .= substr( $seq, $pos );
    }

    return $alignment_str;
}

sub query_alignment_string {
    my ( $bio_seq, $cigar ) = @_;

    my ( $seq, $query_start, $query_end );
    if ( $cigar->{query_strand} eq '-' ) {
        $seq = $bio_seq->revcom->seq;
        $query_start = $bio_seq->length - $cigar->{query_start};
        $query_end   = $bio_seq->length - $cigar->{query_end};
    }
    else {
        $seq = $bio_seq->seq;
        $query_start = $cigar->{query_start};
        $query_end   = $cigar->{query_end};
    }

    my $pos = 0;
    my $alignment_str;

    if ( $query_start > 0 ) {
        $alignment_str .= substr( $seq, 0, $query_start );
        $pos += $query_start;
    }

    for ( @{ $cigar->{operations} } ) {
        my ( $op, $length ) = @$_;
        if ( $op eq 'M' or $op eq 'I' ) {
            $alignment_str .= substr( $seq, $pos, $length );
            $pos += $length;
        }
        else {
            $alignment_str .= '-' x $length;
        }
    }

    if ( $pos < length( $seq ) ) {
        $alignment_str .= substr( $seq, $pos );
    }

    return $alignment_str;
}

sub target_alignment_string_pos {
    my ( $cigar, $target_pos, $target_len ) = @_;

    # $target_pos is 1-based coordinate, convert to zero-based
    $target_pos = $target_pos - 1;

    my ( $alignment_start, $alignment_end );
    if ( $cigar->{target_strand} eq '+' ) {
        $alignment_start = $cigar->{target_start};
        $alignment_end   = $cigar->{target_end} - 1; # convert in-between coordinate to zero-based
    }
    else {
        $alignment_start = $target_len - $cigar->{target_start};
        $alignment_end   = $target_len - $cigar->{target_end} + 1;
        $target_pos      = $target_len - $target_pos - 1;
    }

    my @operations = @{ $cigar->{operations} };
    if ( $alignment_start > 0 ) {
        # Fake a deletion at the start
        unshift @operations, ['D', $alignment_start];
    }
    if ( $alignment_end < $target_len ) {
        # Fake a deletion at the end
        push @operations, ['D', $target_len - $alignment_end + 1 ];
    }

    my $offset = $target_pos;
    my $alignment_pos = 0;

    while ( $offset ) {
        my ( $op, $length ) = @{shift @operations};
        if ( $op eq 'M' or $op eq 'D' ) {
            my $this_offset = min( $offset, $length );
            $alignment_pos  += $this_offset;
            $offset         -= $this_offset;
        }
        elsif ( $op eq 'I' ) {
            $alignment_pos += $length;
        }
    }

    return $alignment_pos;
}

sub alignment_match {
    my ( $query_bio_seq, $target_bio_seq, $cigar, $start, $end ) = @_;

    # $start, $end 1-based co-ordinates, inclusive
    # Expected align_str lengths is ( $start - $end + 1 ).
    # When $start not given, assume 1
    # When end not given, assume $target_bio_seq->length

    $start ||= 1;
    $end   ||= $target_bio_seq->length;

    my $target_align_str = target_alignment_string( $target_bio_seq, $cigar );
    my $query_align_str  = query_alignment_string( $query_bio_seq, $cigar );

    my $pad_total = length( $target_align_str ) - length( $query_align_str );

    my ( $pad_left, $pad_right );

    if ( $cigar->{target_strand} eq '+' ) {
        $pad_left  = $cigar->{target_start} - $cigar->{query_start};
        $pad_right = ($target_bio_seq->length - $cigar->{target_end}) - ($query_bio_seq->length - $cigar->{query_end});
    }
    else {
        $pad_left  = ($target_bio_seq->length - $cigar->{target_start}) - $cigar->{query_start};
        $pad_right = $cigar->{target_end} - ($query_bio_seq->length - $cigar->{query_end});
    }

    if ( $pad_left < 0 ) {
        $target_align_str = join( '', '-' x -$pad_left ) . $target_align_str;
    }
    elsif ( $pad_left > 0 ) {
        $query_align_str = join( '', '-' x $pad_left ) . $query_align_str;
    }

    if ( $pad_right < 0 ) {
        $target_align_str = $target_align_str . join( '', '-' x -$pad_right );
    }
    elsif ( $pad_right > 0 ) {
        $query_align_str = $query_align_str . join( '', '-' x $pad_right );
    }

    if ( length( $target_align_str ) != length( $query_align_str ) ) {
        HTGT::QC::Exception->throw( 'Alignment string length mismatch (target='
                                        . length( $target_align_str) . ', query=' . length( $query_align_str ) . ')' );
    }

    my $sub_seq_start = target_alignment_string_pos( $cigar, $start, $target_bio_seq->length );
    my $sub_seq_end   = target_alignment_string_pos( $cigar, $end,   $target_bio_seq->length );

    if ( $sub_seq_start > $sub_seq_end ) {
        ( $sub_seq_start, $sub_seq_end ) = ( $sub_seq_end, $sub_seq_start );
    }
    my $sub_seq_length = $sub_seq_end - $sub_seq_start + 1;
    my $target_str = substr( $target_align_str, $sub_seq_start, $sub_seq_length );
    my $query_str  = substr( $query_align_str,  $sub_seq_start, $sub_seq_length );
    my $match_str  = join '',
        map { substr( $target_str, $_, 1 ) eq substr( $query_str, $_, 1 ) ? '|' : ' ' }
            0 .. $sub_seq_length-1;

    my $match_count = $match_str =~ tr {|}{|};
    my $length      = length( $match_str );
    my $match_pct   = int( $match_count * 100 / $length );

    return +{
        query_str    => $query_str,
        match_str    => $match_str,
        target_str   => $target_str,
        match_count  => $match_count,
        length       => $length,
        match_pct    => $match_pct
    };
}

sub format_alignment {
    my %params = @_;

    my $line_len   = $params{line_len} || $DISPLAY_LINE_LEN;
    my $header_len = $params{header_len} || $DISPLAY_HEADER_LEN;

    my $fmt = "\%${header_len}s \%s\n" x 3;
    my $t_display_id = $params{target_id} ? substr( $params{target_id}, 0, $header_len )
                                          : 'Target';
    my $q_display_id = $params{query_id}  ? substr( $params{query_id}, 0, $header_len )
                                          : 'Query';

    my $length = length( $params{target_str} );

    my $alignment_str = '';

    my $pos = 0;
    while ( $pos < $length ) {
        my $chunk_size = min( $length - $pos, $line_len );
        $alignment_str .= sprintf( $fmt,
                                   $t_display_id, substr( $params{target_str}, $pos, $chunk_size ),
                                   '',            substr( $params{match_str},  $pos, $chunk_size ),
                                   $q_display_id, substr( $params{query_str},  $pos, $chunk_size )
                               ) . "\n";
        $pos += $chunk_size;
    }

    return $alignment_str;
}

1;

__END__
