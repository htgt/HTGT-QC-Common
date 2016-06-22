package HTGT::QC::Action::Misc::ScfToFasta;

use Moose;
use MooseX::Types::Path::Class;
use Path::Class;
use File::Find::Rule;
use Bio::SeqIO;
use namespace::autoclean;

extends 'HTGT::QC::Action';

override command_names => sub {
    'scf-to-fasta'
};

override abstract => sub {
    'convert all SCF files in the input directory to FASTA format'
};

has input_dir => (
    is       => 'ro',
    isa      => 'Path::Class::Dir',
    coerce   => 1,
    required => 1,
    traits   => [ 'Getopt' ],
    cmd_flag => 'input'
);

has output_file => (
    is       => 'ro',
    isa      => 'Path::Class::File',
    coerce   => 1,
    required => 1,
    traits   => [ 'Getopt' ],
    cmd_flag => 'output'
);

# N.B. this makes no attempt at quality clipping

sub execute {
    my ( $self, $opts, $args ) = @_;

    my $out = Bio::SeqIO->new( -fh => $self->output_file->openw, -format => 'fasta' );

    my @files = File::Find::Rule->file()->name( '*.scf' )->in( $self->input_dir );

    for my $f ( map { file($_) } @files ) {
        $self->log->debug( "Reading $f" );
        ( my $display_id = $f->basename ) =~ s/\.scf$//;
        my $in = Bio::SeqIO->new( -fh => $f->openr, -format => 'scf' );
        my $s = $in->next_seq;
        $s->display_id( $display_id );
        $out->write_seq( $s );
    }
}

__PACKAGE__->meta->make_immutable;

1;

__END__
