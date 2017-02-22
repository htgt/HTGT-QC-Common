package HTGT::QC::Action::AlignReads;
## no critic(RequireUseStrict,RequireUseWarnings)
{
    $HTGT::QC::Action::AlignReads::VERSION = '0.050';
}
## use critic


use Moose;
use MooseX::Types::Path::Class;
use namespace::autoclean;

extends qw( HTGT::QC::Action );

has reads_file => (
    is       => 'ro',
    isa      => 'Path::Class::File',
    traits   => [ 'Getopt' ],
    cmd_flag => 'reads',
    coerce   => 1,
    required => 1
);

__PACKAGE__->meta->make_immutable;

1;

__END__
