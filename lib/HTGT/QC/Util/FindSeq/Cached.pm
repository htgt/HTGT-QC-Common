package HTGT::QC::Util::FindSeq::Cached;

use strict;
use warnings FATAL => 'all';

use Sub::Exporter -setup => {
    exports => [ 'find_seq', 'clear_cache' ],
    groups => {
        default => [ 'find_seq' ]
    }
};

use HTGT::QC::Util::FindSeq ();

{
    my %cached;

    sub clear_cache {
        %cached = ();
    }

    sub find_seq {
        my ( $dir, $seq_id, $format ) = @_;
        unless ( $cached{$format}{$seq_id} ) {
            $cached{$format}{$seq_id} = HTGT::QC::Util::FindSeq::find_seq( $dir, $seq_id, $format );
        }
        return $cached{$format}{$seq_id};        
    }
}

1;

__END__
