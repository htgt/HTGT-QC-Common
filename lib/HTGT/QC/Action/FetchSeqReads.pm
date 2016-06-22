package HTGT::QC::Action::FetchSeqReads;

use Moose;
use MooseX::Types::Path::Class;
use Bio::SeqIO;
use HTGT::QC::Exception;
use namespace::autoclean;

extends qw( HTGT::QC::Action );

has output_file => (
    is       => 'ro',
    isa      => 'Path::Class::File',
    coerce   => 1,
    traits   => [ 'Getopt' ],
    cmd_flag => 'output-file',
    required => 1
);

has seq_out => (
    is         => 'ro',
    isa        => 'Bio::SeqIO',
    traits     => [ 'NoGetopt' ],
    lazy_build => 1
);

sub _build_seq_out {
    my $self = shift;

    my $ofh = $self->output_file->openw
        or HTGT::QC::Exception( 'Failed to open ' . $self->output_file . ' for writing: ' . $! );

    return Bio::SeqIO->new( -fh => $ofh, -format => 'fasta' );
}

__PACKAGE__->meta->make_immutable;

1;

__END__
