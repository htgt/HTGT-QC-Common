package HTGT::QC::Action::PreFilter::Score;

use Moose;
use List::Util qw( sum );
use namespace::autoclean;

extends 'HTGT::QC::Action::PreFilter';

has min_score => (
    is         => 'ro',
    isa        => 'Int',
    traits     => [ 'Getopt' ],
    cmd_flag   => 'min-score',
    lazy_build => 1,
);

sub _build_min_score {
    shift->profile->pre_filter_min_score;
}

override command_names => sub {
    'pre-filter-score'
};

override abstract => sub {
    'filter alignments with a cumulative minimum score criteria'
};

override is_wanted => sub {
    my ( $self, $cigar_for ) = @_;

    my $score = sum( 0, map { $_->{score} } values %{ $cigar_for } );
    $self->log->debug( "Score: $score" );    
    
    return $score >= $self->min_score;
};

__PACKAGE__->meta->make_immutable;

1;

__END__
