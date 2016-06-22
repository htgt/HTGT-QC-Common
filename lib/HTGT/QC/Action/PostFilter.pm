package HTGT::QC::Action::PostFilter;

use Moose;
use MooseX::Types::Path::Class;
use Path::Class;
use HTGT::QC::Exception;
use YAML::Any;
use namespace::autoclean;

extends qw( HTGT::QC::Action );

has output_dir => (
    is       => 'ro',
    isa      => 'Path::Class::Dir',
    traits   => [ 'Getopt' ],
    cmd_flag => 'output-dir',
    required => 1,
    coerce   => 1
);

sub execute {
    my ( $self, $opts, $args ) = @_;

    $self->log->debug( "Running post_filter" );

    for my $input_dir ( map { dir $_ } @{$args} ) {
        for my $query_dir ( $input_dir->children ) {
            my $wanted_count = 0;
            my $top_fail_score = 0;
            my $top_fail;
            for my $target_yaml ( $query_dir->children ) {
                my $analysis = YAML::Any::LoadFile( $target_yaml );
                if ( $self->is_wanted( $analysis ) ) {
                    $wanted_count++;
                    $self->_link_to_out_dir($input_dir, $query_dir, $target_yaml);
                }
                else{
                    my $score = $self->_alignment_score_sum($analysis);
                    if($score > $top_fail_score){
                        $top_fail = $target_yaml;
                        $top_fail_score = $score;
                    }
                }
            }

            # If no valid result found for the well
            # store top failed result so user can see what happened
            # Do not store all failed results as this could be 96 results per well
            if($wanted_count == 0){
                $self->_link_to_out_dir($input_dir, $query_dir, $top_fail);
            }

        }
    }
}

sub _link_to_out_dir{
    my ($self, $input_dir, $query_dir, $target_yaml) = @_;
    my $this_out_dir = $self->output_dir->subdir( $query_dir->relative( $input_dir ) );
    $this_out_dir->mkpath;
    my $out_file = $this_out_dir->file( $target_yaml->basename );
    link $target_yaml, $out_file
        or HTGT::QC::Exception->throw( "link $target_yaml, $out_file: $!" );
}

sub _alignment_score_sum{
    my ($self, $analysis) = @_;
    my $sum = 0;
    foreach my $primer (keys %{ $analysis->{primers} || {} }){
        my $cigar = $analysis->{primers}->{$primer}->{cigar};
        if($cigar){
            $sum += $cigar->{score};
        }
    }
    return $sum;
}

sub is_wanted {
    confess 'is_wanted() must be overridden by a subclass';
}

__PACKAGE__->meta->make_immutable;

1;

__END__
