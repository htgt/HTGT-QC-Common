package HTGT::QC::Util::ListLatestRuns;

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

#this gets all active runs (so no sorting or anything), and will hopefully be fastish
sub get_active_runs {
    my ( $self ) = shift;

    #get all directories with a params file that haven't ended yet
    my @active_runs = grep { $_->is_dir and -e $_->file( "params.yaml" ) and not -e $_->file( "ended.out" ) }
                        $self->config->basedir->children();

    my @run_data;
    for my $run_dir ( @active_runs ) {
        #if it is failed then it will be ending very soon, so dont count it.
        next if -e $run_dir->file( "failed.out" );

        push @run_data, $self->get_run_data( {
            run_id => $run_dir->basename,
            ctime  => $run_dir->file( "params.yaml" )->stat->ctime,
        } );
    }

    return \@run_data;
}

sub get_latest_run_data {
    my ( $self ) = shift;

    #get all directories with a params.yaml file.
    my @child_dirs = grep { $_->is_dir and -e $_->file( "params.yaml" ) } $self->config->basedir->children();

    #sort them by time created
    my @runs = reverse sort { $a->{ ctime } <=> $b->{ ctime } }
        map { { run_id => $_->dir_list(-1), ctime => $_->file( "params.yaml" )->stat->ctime } }
            @child_dirs;

    my $max_index = min( scalar @runs, $self->limit ) - 1;

    my @run_data;
    for my $run ( @runs[0..$max_index] ) {
        push @run_data, $self->get_run_data( $run );
    }

    return \@run_data;
}

sub get_run_data {
    my ( $self, $run ) = @_;
    #run is a hashref with ctime and run_id

    my $run_dir = $self->config->basedir->subdir( $run->{ run_id } );

    #we only have dirs with a params file so we know this exists
    my $params = YAML::Any::LoadFile( $run_dir->file( 'params.yaml' ) );

    next unless $params->{ sequencing_projects };

    #the head of this list is the latest stage that was run
    my ( $newest_time, @stages ) = $self->get_time_sorted_filenames( $run->{ run_id } );

    #a note about the failed/ended ended status:
    #the existence of these files determines the status of the run. 
    #if failed.out exists there was an exception or the run was killed,
    #if ended.out exists there are no processes left running, either because it was killed or finished.
    #ended does NOT imply success. if something is failed it will also probably be ended

    return {
            qc_run_id       => $run->{ run_id },
            created         => scalar localtime $run->{ ctime },
            profile         => $params->{ profile },
            seq_projects    => join( '; ', @{ $params->{ sequencing_projects } } ),
            template_plate  => $params->{ template_plate },
            last_stage      => shift @stages, #top file is the newest
            last_stage_time => $newest_time,
            previous_stages => \@stages,
            failed          => -e $run_dir->file( 'failed.out' ),
            ended           => -e $run_dir->file( 'ended.out' ),
            is_escell       => $self->config->profile( $params->{ profile } )->is_es_cell(),
    };
}

#return all the filenames from newest to oldest
sub get_time_sorted_filenames {
    my ( $self, $qc_run_id ) = @_;

    my @outfiles = $self->config->basedir->subdir( $qc_run_id, 'output' )->children;

    #allow a run without any ouput to be displayed. it is likely just pending
    return ( "-", undef ) unless @outfiles;

    my @time_sorted_outfiles = reverse sort { $a->stat->ctime <=> $b->stat->ctime } @outfiles;

    #return newest ctime & extract a list of just the filenames, we dont care about the directories.
    return ( scalar localtime $time_sorted_outfiles[0]->stat->ctime,
             map { $_->basename =~ /^(.*)\.out$/ } @time_sorted_outfiles );
}

__PACKAGE__->meta->make_immutable;

1;

__END__
