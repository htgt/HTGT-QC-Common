package HTGT::QC::Action::FetchTemplateData;

use Moose;
use MooseX::Types::Path::Class;
use YAML::Any;
use namespace::autoclean;

extends qw( HTGT::QC::Action );

has output_file => (
    is       => 'ro',
    isa      => 'Path::Class::File',
    coerce   => 1,
    required => 1,
    traits   => [ 'Getopt' ],
    cmd_flag => 'output-file',
);

sub execute {
    my ( $self, $opts, $args ) = @_;

    my $params = $self->get_eng_seq_params( $args->[0] );

    YAML::Any::DumpFile( $self->output_file, $params );
}

sub get_eng_seq_params {
    confess "get_eng_seq_params() must be implemented by a subclass";
}

__PACKAGE__->meta->make_immutable;

1;

__END__
