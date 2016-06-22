package HTGT::QC::Util::SeqReads;

use Moose::Role;
use Bio::SeqIO;
use namespace::autoclean;

has seq_reads_files => (
    isa      => 'ArrayRef[Str]',
    traits   => [ 'Getopt', 'Array' ],
    cmd_flag => 'seq-reads',
    required => 1,
    handles  => {
        seq_reads_files => 'elements'
    }
);

has seq_reads => (
    isa        => 'HashRef',
    traits     => [ 'NoGetopt', 'Hash' ],
    lazy_build => 1,
    handles    => {
        seq_read_ids => 'keys',
        seq_read     => 'get'
    }    
);

sub _build_seq_reads {
    my $self = shift;

    my %seq_read_for;

    for my $filename ( $self->seq_reads_files ) {
        my $seq_in = Bio::SeqIO->new( -file => $filename, -format => 'fasta' );    
        while ( my $seq = $seq_in->next_seq ) {
            $seq_read_for{ $seq->display_id } = $seq;
        }
    }    

    return \%seq_read_for;
}

1;

__END__
