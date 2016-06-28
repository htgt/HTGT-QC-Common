package HTGT::QC::Action::Persist;
## no critic(RequireUseStrict,RequireUseWarnings)
{
    $HTGT::QC::Action::Persist::VERSION = '0.046';
}
## use critic


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
