package HTGT::QC::Exception;
## no critic(RequireUseStrict,RequireUseWarnings)
{
    $HTGT::QC::Exception::VERSION = '0.013';
}
## use critic


use Moose;
use namespace::autoclean;

extends 'Throwable::Error';

__PACKAGE__->meta->make_immutable( inline_constructor => 0 );

1;
