package HTGT::QC::Util::ListLatestRuns;
## no critic(RequireUseStrict,RequireUseWarnings)
{
    $HTGT::QC::Util::ListLatestRuns::VERSION = '0.007';
}
## use critic


use Moose;
use YAML::Any;
use List::Util qw( min );
use namespace::autoclean;

with 'MooseX::Log::Log4perl';

has limit => (
    is => 'ro',
    isa => 'Int',
    default => 50
);

has config => (
    is => 'ro',
    isa => 'HTGT::QC::Config',
    required => 1
);

sub get_latest_run_data{
    my ( $self ) = shift;

    my @child_dirs;
    my @children = $self->config->basedir->children;
    for my $child( @children ){
        push @child_dirs, $child if $child->is_dir and -e $child->file("params.yaml");
    }
    my @runs = reverse sort { $a->{ctime} <=> $b->{ctime} }
        map { { run_id => $_->dir_list(-1), ctime => $_->file("params.yaml")->stat->ctime } }
            @child_dirs;

    my $max_index = min( scalar @runs, $self->limit ) - 1;

    my @run_data;
    for my $run ( @runs[0..$max_index] ){
        my $params_file = $self->config->basedir->subdir( $run->{run_id} )->stringify
            . '/params.yaml';
        unless ( -e $params_file ){
            push @run_data, (
                {
                    qc_run_id    => $run->{run_id}
                }
            );
            next;
        }

        my $params = YAML::Any::LoadFile( $params_file );
        next unless $params->{sequencing_projects};
        my ( $oldest_stage, $oldest_stage_time, $previous_stages ) = $self->get_last_stage_details( $run->{run_id} );
        my ( $failed, $ended ) = $self->get_run_progress( $run->{run_id} );

        push @run_data, (
            {
                qc_run_id       => $run->{run_id},
                created         => scalar localtime($run->{ctime}),
                profile         => $params->{profile},
                seq_projects    => join('; ', @{$params->{sequencing_projects}}),
                template_plate  => $params->{template_plate},
                last_stage      => $oldest_stage,
                last_stage_time => $oldest_stage_time,
                previous_stages => $previous_stages,
                failed          => $failed,
                ended           => $ended,
            }
        );
    }

    return \@run_data;
}

sub get_run_progress {
    my ( $self, $qc_run_id ) = @_;

    #if a file exists it determines the status, note it is possible (and likely) to be failed and ended.
    #failed just means there was an exception or it was killed
    #ended means the processes are no longer running, it is called ended because finished implies success.
    my $failed = $self->config->basedir->subdir( $qc_run_id )->file( 'failed.out' );
    my $ended = $self->config->basedir->subdir( $qc_run_id )->file( 'ended.out' );

    #-e returns true if a file exists
    return ( -e $failed, -e $ended );

}

sub get_last_stage_details {
    my ( $self, $qc_run_id ) = @_;

    my @outfiles = $self->config->basedir->subdir( $qc_run_id )->subdir('output')->children;

    # Avoid interface error when user goes to run list before any output files
    # have been written
    return ( "-", "-" ) unless @outfiles;

    my @time_sorted_outfiles = reverse sort { $a->stat->ctime <=> $b->stat->ctime } @outfiles;

    # get just the filenames, we can infer the directories later.
    # map returns $1 from the regex by default in this context.
    my @filenames = map { $_->basename =~ /^(.*)\.out$/ } @time_sorted_outfiles;

    my $oldest = shift @time_sorted_outfiles; #get the most recent file
    my $oldest_stage_time = scalar localtime $oldest->stat->ctime; #get a more readable time
    my $oldest_stage = shift @filenames; #top of filenames is the same as $oldest, so just take that.

    return ( $oldest_stage, $oldest_stage_time, \@filenames );
}

__PACKAGE__->meta->make_immutable;

1;

__END__
