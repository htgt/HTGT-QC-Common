package HTGT::QC::Action::PreFilter::All;

use Moose;
use List::Util qw( sum );
use namespace::autoclean;

extends 'HTGT::QC::Action::PreFilter';

override command_names => sub {
    'pre-filter-all'
};

override abstract => sub {
    'filter alignments with no minimum criteria'
};

override is_wanted => sub {
    1
};

__PACKAGE__->meta->make_immutable;

1;

__END__
