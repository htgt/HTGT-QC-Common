package HTGT::QC::Action::PostFilter::NumPrimers;

use Moose;
use namespace::autoclean;

extends 'HTGT::QC::Action::PostFilter';

override command_names => sub {
    'post-filter-num-primers'
};

override abstract => sub {
    'filter analysis with a minimum threshold on the number of valid primers'
};

has min_primers => (
    is         => 'ro',
    isa        => 'Int',
    traits     => [ 'Getopt' ],
    cmd_flag   => 'min-primers',
    lazy_build => 1,
);

sub _build_min_primers {
    shift->profile->post_filter_min_primers;
}

override is_wanted => sub {
    my ( $self, $analysis ) = @_;
    
    # Checks that the number of primer passes *for primers that hit genomic* is >= min_primers
    my $num_valid_primers = grep { $self->profile->is_genomic_pass($_) } values %{ $analysis->{primers} };
    $self->log->debug( "$num_valid_primers valid primers for $analysis->{query_well} $analysis->{target_id}" );

    $num_valid_primers >= $self->min_primers;
};

__PACKAGE__->meta->make_immutable;

1;

__END__
