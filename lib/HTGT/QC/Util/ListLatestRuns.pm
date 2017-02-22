package HTGT::QC::Util::ListLatestRuns;
## no critic(RequireUseStrict,RequireUseWarnings)
{
    $HTGT::QC::Util::ListLatestRuns::VERSION = '0.050';
}
## use critic


use Moose;
use YAML::Any;
use List::Util qw( min );
use namespace::autoclean;
use HTGT::QC::Util::FileAccessServer;
use Data::Dumper;
use Path::Class;
use Date::Parse qw(str2time);

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

has file_api_url => (
    is       => 'ro',
    isa      => 'Str',
    default  => sub { $ENV{ FILE_API_URL } }
);

has file_api => (
    is       => 'ro',
    isa      => 'HTGT::QC::Util::FileAccessServer',
    lazy_build => 1,
    handles => [ qw(fileserver_get_json get_file_content post_file_content) ]
);

sub _build_file_api {
    my $self = shift;
    $self->log->debug("Building file api with URL ".$self->file_api_url);
    return HTGT::QC::Util::FileAccessServer->new({
        file_api_url => $self->file_api_url,
    });
}

sub fetch_error_file{
    my ( $self, $run_id, $stage ) = @_;

    my $file_path = $self->config->basedir->subdir( $run_id )->subdir( 'error' )->file( $stage . '.err' );
    my $content = $self->get_file_content( $file_path );

    my @lines = split "\n", $content;

    return @lines;
}

#this gets all active runs (so no sorting or anything), and will hopefully be fastish
# NB: rewritten to get file info via web api but I can't find any calls to this method
# so have not tested it. af11 2015-08-12
sub get_active_runs {
    my ( $self ) = shift;

    my $dir_content = $self->fileserver_get_json( $self->config->basedir );

    my @child_dir_content = map { $self->fileserver_get_json( $_ ) } @$dir_content;

    my @run_data;
    foreach my $content (@child_dir_content){
        # Must have a param file
        my ($param_file) = grep { $_ =~ /params\.yaml$/ } @$content;
        next unless $param_file;

        # But no ended file
        next if (grep { $_ =~ /ended\.out$/ } @$content);

        #if it is failed then it will be ending very soon, so dont count it.
        next if (grep { $_ =~ /failed\.out$/ } @$content);

        my $ctime = $self->fileserver_get_json( $param_file, { stat => 'true'} )->{ctime};
        my $path = file($param_file);
        my $run_id = $path->dir->dir_list(-1);

        push @run_data, $self->get_run_data({
            run_id => $run_id,
            ctime  => $ctime,
            failed => 0,
            ended  => 0,
        });

    }
    return \@run_data;
}

sub get_latest_run_data {
    my ( $self ) = shift;

    my $dir_content = $self->fileserver_get_json( $self->config->basedir );

    my @child_dir_content = map { $self->fileserver_get_json( $_ ) } @$dir_content;

    my @runs_tmp;
    foreach my $content (@child_dir_content){
        my ($param_file) = grep { $_ =~ /params\.yaml$/ } @$content;
        if($param_file){
            my $ctime = $self->fileserver_get_json( $param_file, {stat => 'true'} )->{ctime};
            my $path = file($param_file);
            my $run_id = $path->dir->dir_list(-1);
            my $failed = grep { $_ =~ /failed\.out$/ } @$content;
            my $ended  = grep { $_ =~ /ended\.out$/ } @$content;
            push @runs_tmp, {
                run_id => $run_id,
                ctime  => $ctime,
                failed => $failed,
                ended  => $ended,
            };
        }
    }

    my @runs = reverse sort { $a->{ ctime } cmp $b->{ ctime } } @runs_tmp;

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
    my $param_path = $run_dir->file( 'params.yaml' )->stringify;
    my $params_file = $self->get_file_content( $param_path );

    my $params = YAML::Any::Load( $params_file );

    next unless $params->{ sequencing_projects };

    #the head of this list is the latest stage that was run
    my ( $newest_time, @stages ) = $self->get_time_sorted_filenames( $run->{ run_id } );

    #a note about the failed/ended ended status:
    #the existence of these files determines the status of the run.
    #if failed.out exists there was an exception or the run was killed,
    #if ended.out exists there are no processes left running, either because it was killed or finished.
    #ended does NOT imply success. if something is failed it will also probably be ended

    my $created = scalar localtime (str2time( $run->{ ctime } ));
    my $last_stage_time = scalar localtime (str2time( $newest_time));

    return {
            qc_run_id       => $run->{ run_id },
            created         => $created,
            profile         => $params->{ profile },
            seq_projects    => join( '; ', @{ $params->{ sequencing_projects } } ),
            template_plate  => $params->{ template_plate },
            last_stage      => shift @stages, #top file is the newest
            last_stage_time => $last_stage_time,
            previous_stages => \@stages,
            failed          => $run->{failed},
            ended           => $run->{ended},
            is_escell       => $self->config->profile( $params->{ profile } )->is_es_cell(),
    };
}

#return all the filenames from newest to oldest
sub get_time_sorted_filenames {
    my ( $self, $qc_run_id ) = @_;

    my $output_path = $self->config->basedir->subdir($qc_run_id, 'output');
    my $outfiles = $self->fileserver_get_json( $output_path->stringify );

    return ("-", undef) unless @$outfiles;

    # partial Schwartzian transform thing so we only have to fetch the stats for each file once
    my @time_sorted_outfiles = reverse sort { $a->[1]->{'ctime'} cmp $b->[1]->{'ctime'} }
                               map { [ $_, $self->fileserver_get_json( $_, { stat => 'true' } ) ]}
                               @$outfiles;

    my $newest_ctime = $time_sorted_outfiles[0]->[1]->{ctime};
    my @filenames = map { file($_->[0])->basename =~ /^(.*)\.out$/ } @time_sorted_outfiles;

    return ($newest_ctime, @filenames);
}

__PACKAGE__->meta->make_immutable;

1;

__END__
