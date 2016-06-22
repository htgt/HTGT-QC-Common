package HTGT::QC::Action::RunAnalysis;

use Moose;
use Bio::SeqIO;
use YAML::Any;
use namespace::autoclean;

extends qw( HTGT::QC::Action );

has seq_reads_file => (
    is       => 'ro',
    isa      => 'Path::Class::File',
    traits   => [ 'Getopt' ],
    cmd_flag => 'seq-reads',
    coerce   => 1,
    required => 1
);

has seq_reads => (
    is         => 'ro',
    isa        => 'HashRef',
    traits     => [ 'NoGetopt' ],
    lazy_build => 1
);

has template_params_file => (
    is       => 'ro',
    isa      => 'Path::Class::File',
    traits   => [ 'Getopt' ],
    cmd_flag => 'template-params',
    coerce   => 1,
    required => 0,
);

has template_params => (
    is         => 'ro',
    isa        => 'Maybe[HashRef]',
    traits     => [ 'NoGetopt' ],
    lazy_build => 1,
);

sub _build_template_params {
    my $self = shift;
    if ( $self->template_params_file ){
        return YAML::Any::LoadFile( $self->template_params_file );
    }

    return;
}

sub _build_seq_reads {
    my $self = shift;
    
    my $seq_in = Bio::SeqIO->new( -fh => $self->seq_reads_file->openr, -format => 'fasta' );
    
    my %seq_read_for;

    while ( my $seq = $seq_in->next_seq ) {
        ( my $key = $seq->display_id ) =~ s/\s.+$//;
        $seq_read_for{$key} = $seq;
    }

    return \%seq_read_for;
}

__PACKAGE__->meta->make_immutable;

1;

__END__
