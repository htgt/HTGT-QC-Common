package HTGT::QC::Exception;

use Moose;
use namespace::autoclean;

extends 'Throwable::Error';

__PACKAGE__->meta->make_immutable( inline_constructor => 0 );

1;
