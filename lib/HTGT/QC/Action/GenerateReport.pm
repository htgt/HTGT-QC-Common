package HTGT::QC::Action::GenerateReport;

use Moose;
use MooseX::Types::Path::Class;
use namespace::autoclean;

extends qw( HTGT::QC::Action );

has analysis_dir => (
    is       => 'ro',
    isa      => 'Path::Class::Dir',
    traits   => [ 'Getopt' ],
    cmd_flag => 'analysis',
    required => 1,
    coerce   => 1
);

has output_file => (
    is       => 'ro',
    isa      => 'Path::Class::File',
    traits   => [ 'Getopt' ],
    cmd_flag => 'output-file',
    required => 1,
    coerce   => 1
);

__PACKAGE__->meta->make_immutable;

1;

__END__
