package HTGT::QC::Action::Persist;

use strict;
use warnings FATAL => 'all';

use Moose;
use MooseX::Types::Path::Class;
use namespace::autoclean;

extends qw( HTGT::QC::Action );

has qc_run_id => (
    is       => 'ro',
    isa      => 'Str',
    traits   => [ 'Getopt' ],
    cmd_flag => 'run-id',
    required => 1
);

has analysis_dir => (
    is         => 'ro',
    isa        => 'Path::Class::Dir',
    traits     => [ 'Getopt' ],
    cmd_flag   => 'analysis-dir',
    required   => 1,
    coerce     => 1
);

1;

__END__
