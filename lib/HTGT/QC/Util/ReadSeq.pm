package HTGT::QC::Util::ReadSeq;

use strict;
use warnings FATAL => 'all';

use Sub::Exporter -setup => {
    exports => [ qw( read_seq ) ],
    groups => {
        default => [ qw( read_seq ) ]
    }
};

use Bio::SeqIO;
use Log::Log4perl ':easy';

sub read_seq {    
    my ( $filename, $format ) = @_;

    my @args = ( -file => $filename );
    push @args, '-format', $format if defined $format;
        
    my $seq_io = Bio::SeqIO->new( @args )
        or LOGDIE "Error reading $filename";

    my $seq = $seq_io->next_seq
        or LOGDIE "Failed to read sequence from $filename";

    return $seq;
}

1;

__END__
