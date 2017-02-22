package HTGT::QC::Util::Alignment;
## no critic(RequireUseStrict,RequireUseWarnings)
{
    $HTGT::QC::Util::Alignment::VERSION = '0.050';
}
## use critic


use strict;
use warnings FATAL => 'all';

use Sub::Exporter -setup => {
    exports => [
        qw( target_alignment_string
            reduced_query_alignment_string
            reduced_target_alignment_string
            query_alignment_string
            target_alignment_string_pos
            alignment_match
            alignment_match_on_target
            format_alignment
            )
    ],
};

use Const::Fast;
use List::Util qw( min sum );
use Log::Log4perl ':easy';
use Data::Dump 'pp';
use HTGT::QC::Exception;
use Bio::Perl qw( revcom );

const my $DISPLAY_HEADER_LEN => 12;
const my $DISPLAY_LINE_LEN   => 72;

# one base per target, BUT with a "Q" written when the query
# has an insertion relative to the target
sub reduced_target_alignment_string {
    my ( $bio_seq, $cigar ) = @_;

    my ( $seq, $target_start, $target_end );
    if ( $cigar->{target_strand} eq '-' ) {
        $seq          = $bio_seq->revcom->seq;
        $target_start = $bio_seq->length - $cigar->{target_start};
        $target_end   = $bio_seq->length - $cigar->{target_end};
    }
    else {
        $seq          = $bio_seq->seq;
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
        else {
            # $op eq 'I'
            # have to go to the previous base and replace it with a "Q"
            $alignment_str = substr( $alignment_str, 0, length($alignment_str) - 1 ) . "Q";
        }
    }

    if ( $pos < length($seq) ) {
        $alignment_str .= substr( $seq, $pos );
    }

    return $alignment_str;
}

# one base per target bioseq:
# The actual emitted string (to account for mismatches)
# AND a 'result' string which indicates M or D but
# completely omits insertions relative to target
sub reduced_query_alignment_string {
    my ( $query_bio_seq, $cigar, $target_bio_seq ) = @_;

    my ( $seq, $query_start, $query_end );
    # should match any reverse primer reads
    if ( $cigar->{query_strand} eq '-' ) {
        $seq         = $query_bio_seq->revcom->seq;
        $query_start = $query_bio_seq->length - $cigar->{query_start};
        $query_end   = $query_bio_seq->length - $cigar->{query_end};
    }
    # should match forward primer reads
    else {
        $seq         = $query_bio_seq->seq;
        $query_start = $cigar->{query_start};
        $query_end   = $cigar->{query_end};
    }

    #first work out how much of the query lies to the left or right of the target
    my ( $pad_left, $pad_right );
    my $pos_on_reference = 0;
    if ( $cigar->{target_strand} eq '+' ) {
        $pad_left         = $cigar->{target_start} - $query_start;
        $pos_on_reference = $cigar->{target_start};
        $pad_right        = ( $target_bio_seq->length - $cigar->{target_end} )
            - ( $query_bio_seq->length - $query_end );
    }
    # this branch has not been used yet, so calculations may be wrong
    else {
        $pad_left         = ( $target_bio_seq->length - $cigar->{target_start} ) - $query_start;
        $pad_right        = $cigar->{target_end} - $query_end;
        $pos_on_reference = $target_bio_seq->length - $cigar->{target_start};
    }

    # If the query starts to the left of the target, then the pos_on_target starts with a neg offset
    # If the query starts to the right of the target, then pos_on_target has a positive offset
    # We _need_ this pos_on_target to correctly catalogue the insertions that we find when building
    # the align string relative to reference
    my %insertions;

    my $pos = 0;
    my $query_alignment_str;

    #First produce the unadulerated string, (then either pad or trim it to the target as necc)
    if ( $query_start > 0 ) {
        $query_alignment_str .= substr( $seq, 0, $query_start );
        $pos              += $query_start;
    }

    for ( @{ $cigar->{operations} } ) {
        my ( $op, $length ) = @$_;
        if ( $op eq 'M' ) {
            $query_alignment_str .= substr( $seq, $pos, $length );
            $pos              += $length;
            $pos_on_reference += $length;
        }
        elsif ( $op eq 'I' ) {
            # instead of adding the whole insertion, add a single Q at this point
            #$query_alignment_str .= "Q";
            my $insertion_string = substr( $seq, $pos, $length );
            $insertions{$pos_on_reference} = $insertion_string;
            $pos += $length;
        }
        # deletion
        else {
            $query_alignment_str .= '-' x $length;
            $pos_on_reference += $length;
        }
    }

    if ( $pos < length($seq) ) {
        $query_alignment_str .= substr( $seq, $pos );
    }

    # Now you have a piece of query sequence which either matches the target or has a '-' for each target base
    # The insertions relative have been obscured completely, but will be caught the 'insertions' hash
    # Now pad left or right (or truncate) to further match target
    if ( $pad_left < 0 ) {
        #clip $pad_left off beginning of string
        $query_alignment_str = substr( $query_alignment_str, abs($pad_left) );
        $pad_left = 0;
    }

    if ( $pad_right < 0 ) {
        #clip $pad_right off end of string
        $query_alignment_str
            = substr( $query_alignment_str, 0, length($query_alignment_str) - abs($pad_right) );
        $pad_right = 0;
    }

    if ( $pad_left > 0 ) {
        $query_alignment_str = join( '', 'X' x $pad_left ) . $query_alignment_str;
    }

    if ( $pad_right > 0 ) {
        $query_alignment_str = $query_alignment_str . join( '', 'X' x $pad_right );
    }

    return ( $query_alignment_str, \%insertions );
}

sub target_alignment_string {
    my ( $bio_seq, $cigar ) = @_;

    my ( $seq, $target_start, $target_end );
    if ( $cigar->{target_strand} eq '-' ) {
        $seq          = $bio_seq->revcom->seq;
        $target_start = $bio_seq->length - $cigar->{target_start};
        $target_end   = $bio_seq->length - $cigar->{target_end};
    }
    else {
        $seq          = $bio_seq->seq;
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
        else {    # $op eq 'I'
            $alignment_str .= '-' x $length;
        }
    }

    if ( $pos < length($seq) ) {
        $alignment_str .= substr( $seq, $pos );
    }

    return $alignment_str;
}

sub query_alignment_string {
    my ( $bio_seq, $cigar ) = @_;

    my ( $seq, $query_start, $query_end );
    if ( $cigar->{query_strand} eq '-' ) {
        $seq         = $bio_seq->revcom->seq;
        $query_start = $bio_seq->length - $cigar->{query_start};
        $query_end   = $bio_seq->length - $cigar->{query_end};
    }
    else {
        $seq         = $bio_seq->seq;
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

    if ( $pos < length($seq) ) {
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
        $alignment_end   = $cigar->{target_end} - 1;   # convert in-between coordinate to zero-based
    }
    else {
        $alignment_start = $target_len - $cigar->{target_start};
        $alignment_end   = $target_len - $cigar->{target_end} + 1;
        $target_pos      = $target_len - $target_pos - 1;
    }

    my @operations = @{ $cigar->{operations} };
    if ( $alignment_start > 0 ) {
        # Fake a deletion at the start
        unshift @operations, [ 'D', $alignment_start ];
    }
    if ( $alignment_end < $target_len ) {
        # Fake a deletion at the end
        push @operations, [ 'D', $target_len - $alignment_end + 1 ];
    }

    my $offset        = $target_pos;
    my $alignment_pos = 0;

    while ($offset) {
        my ( $op, $length ) = @{ shift @operations };
        if ( $op eq 'M' or $op eq 'D' ) {
            my $this_offset = min( $offset, $length );
            $alignment_pos += $this_offset;
            $offset -= $this_offset;
        }
        elsif ( $op eq 'I' ) {
            $alignment_pos += $length;
        }
    }

    return $alignment_pos;
}

sub alignment_match_on_target {
    my ( $query_bio_seq, $target_bio_seq, $cigar ) = @_;

    # $start, $end 1-based co-ordinates, inclusive
    # Expected align_str lengths is ( $start - $end + 1 ).
    # When $start not given, assume 1
    # When end not given, assume $target_bio_seq->length

    my $target_align_str = reduced_target_alignment_string( $target_bio_seq, $cigar );
    my ( $query_align_str, $insertions )
        = reduced_query_alignment_string( $query_bio_seq, $cigar, $target_bio_seq );

    if ( length($target_align_str) != length($query_align_str) ) {
        HTGT::QC::Exception->throw( 'Alignment string length mismatch (target='
                . length($target_align_str)
                . ', query='
                . length($query_align_str)
                . ')' );
    }

    my $well   = $cigar->{query_well};
    my $primer = $cigar->{query_primer};

    my $full_match_string = "";

    # We want to write out a full string along the whole target sequence, of either D's Q's M's or X's.
    # The cigar "starts" in the target sequence at the position $cigar->{target_start} so we pad that portion with X's
    my $alignment_target_start = $cigar->{target_start};
    my $alignment_target_end   = $cigar->{target_end};
    if ( $cigar->{target_strand} eq '-' ) {
        $alignment_target_start = $query_bio_seq->length - $cigar->{target_start};
        $alignment_target_end   = $query_bio_seq->length - $cigar->{target_end};
    }

    $full_match_string .= 'X' x $alignment_target_start;

    for ( @{ $cigar->{operations} } ) {
        my ( $op, $length ) = @$_;
        if ( $op eq 'D' or $op eq 'M' ) {
            $full_match_string .= $op x $length;
        }
        else {

           #for an insertion, trim the last character off the match string and replace it with a "Q"
            $full_match_string
                = substr( $full_match_string, 0, length($full_match_string) - 1 ) . "Q";
        }
    }
    if ( length($full_match_string) < length($target_align_str) ) {
        $full_match_string .= "X" x ( length($full_match_string) - length($target_align_str) );
    }

    return (
        {   well              => $well,
            primer            => $primer,
            query_align_str   => $query_align_str,
            target_align_str  => $target_align_str,
            full_match_string => $full_match_string,
            insertion_details => $insertions,
        }
    );
}

sub alignment_match {
    my ( $query_bio_seq, $target_bio_seq, $cigar, $start, $end ) = @_;

    # $start, $end 1-based co-ordinates, inclusive
    # Expected align_str lengths is ( $start - $end + 1 ).
    # When $start not given, assume 1
    # When end not given, assume $target_bio_seq->length

    $start ||= 1;
    $end   ||= $target_bio_seq->length;

    my $orig_target_str = substr($target_bio_seq->seq, $start, ($end-$start)+1);
    if($cigar->{target_strand} eq '-'){
        $orig_target_str = revcom($orig_target_str)->seq;
    }

    my $target_align_str = target_alignment_string( $target_bio_seq, $cigar );
    my $query_align_str = query_alignment_string( $query_bio_seq, $cigar );

    my $pad_total = length($target_align_str) - length($query_align_str);

    my ( $pad_left, $pad_right );

    if ( $cigar->{target_strand} eq '+' ) {
        my $alignment_query_start = $cigar->{query_start};
        my $alignment_query_end   = $cigar->{query_end};

       # If the query seq is '-' then the query coordinates presented by the cigar are on the neg strand
       # However the align-string has oriented the query string to match the target (pos strand) so we
       # have to first revcomp the query coordinates to do the right padding.
        if ( $cigar->{query_strand} eq '-' ) {
            $alignment_query_start = $query_bio_seq->length - $cigar->{query_start};
            $alignment_query_end   = $query_bio_seq->length - $cigar->{query_end};
        }
        $pad_left  = $cigar->{target_start} - $alignment_query_start;
        $pad_right = ( $target_bio_seq->length - $cigar->{target_end} )
            - ( $query_bio_seq->length - $alignment_query_end );
    }
    else {
        $pad_left = ( $target_bio_seq->length - $cigar->{target_start} ) - $cigar->{query_start};
        $pad_right = $cigar->{target_end} - ( $query_bio_seq->length - $cigar->{query_end} );
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

    if ( length($target_align_str) != length($query_align_str) ) {
        HTGT::QC::Exception->throw( 'Alignment string length mismatch (target='
                . length($target_align_str)
                . ', query='
                . length($query_align_str)
                . ')' );
    }

    my $sub_seq_start = target_alignment_string_pos( $cigar, $start, $target_bio_seq->length );
    my $sub_seq_end   = target_alignment_string_pos( $cigar, $end,   $target_bio_seq->length );

    if ( $sub_seq_start > $sub_seq_end ) {
        ( $sub_seq_start, $sub_seq_end ) = ( $sub_seq_end, $sub_seq_start );
    }
    my $sub_seq_length = $sub_seq_end - $sub_seq_start + 1;
    my $target_str     = substr( $target_align_str, $sub_seq_start, $sub_seq_length );
    my $query_str      = substr( $query_align_str, $sub_seq_start, $sub_seq_length );
    my $match_str      = join '',
        map { substr( $target_str, $_, 1 ) eq substr( $query_str, $_, 1 ) ? '|' : ' ' }
        0 .. $sub_seq_length - 1;

    my $match_count = $match_str =~ tr {|}{|};
    my $length      = length($match_str);
    my $match_pct   = int( $match_count * 100 / $length );

    unless($match_str =~ /\|/){
        # There is no match to the target region so we report
        # the target region sequence taken directly from the eng_seq
        WARN "No match to target region";
        $target_str = $orig_target_str;
    }

    return {
        query_str   => $query_str,
        match_str   => $match_str,
        target_str  => $target_str,
        match_count => $match_count,
        length      => $length,
        match_pct   => $match_pct
    };
}

sub format_alignment {
    my %params = @_;

    my $line_len   = $params{line_len}   || $DISPLAY_LINE_LEN;
    my $header_len = $params{header_len} || $DISPLAY_HEADER_LEN;

    my $fmt = "\%${header_len}s \%s\n" x 3;
    my $t_display_id = $params{target_id} ? substr( $params{target_id}, 0, $header_len ) : 'Target';
    my $q_display_id = $params{query_id} ? substr( $params{query_id}, 0, $header_len ) : 'Query';

    my $length = length( $params{target_str} );

    my $alignment_str = '';

    my $pos = 0;
    while ( $pos < $length ) {
        my $chunk_size = min( $length - $pos, $line_len );
        $alignment_str .= sprintf( $fmt,
            $t_display_id, substr( $params{target_str}, $pos, $chunk_size ),
            '',            substr( $params{match_str},  $pos, $chunk_size ),
            $q_display_id, substr( $params{query_str},  $pos, $chunk_size ) )
            . "\n";
        $pos += $chunk_size;
    }

    return $alignment_str;
}

1;
