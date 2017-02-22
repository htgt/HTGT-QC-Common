package HTGT::QC::Util::KillQCFarmJobs;
## no critic(RequireUseStrict,RequireUseWarnings)
{
    $HTGT::QC::Util::KillQCFarmJobs::VERSION = '0.050';
}
## use critic


use Moose;
use YAML::Any;
use List::Util qw( min );
use IPC::Run ();
use namespace::autoclean;

with 'MooseX::Log::Log4perl';

has qc_run_id => (
    is       => 'ro',
    isa      => 'Str',
    required => 1
);

has config => (
    is       => 'ro',
    isa      => 'HTGT::QC::Config',
    required => 1
);

has farm_job_runner => (
    is       => 'ro',
    isa      => 'WebAppCommon::Util::FarmJobRunner',
    lazy_build => 1,
);


sub _build_farm_job_runner{
    return WebAppCommon::Util::FarmJobRunner->new({
        dry_run => 0,
        bsub_wrapper => '/nfs/team87/farm3_lims2_vms/conf/run_in_farm3_af11'
    });
}

has file_api => (
    is    => 'ro',
    isa   => 'HTGT::QC::Util::FileAccessServer',
    lazy_build => 1,
);

sub _build_file_api{
    my $lustre_server = $ENV{ FILE_API_URL }
        or die "FILE_API_URL environment variable not set";
    return HTGT::QC::Util::FileAccessServer->new({ file_api_url => $lustre_server });
}
sub kill_unfinished_farm_jobs {
    #bsub qc kill-and-notify --config file --run-id FD0C-...
    #essentially, like before, just a handy wrapper for bsubbing the kills
    #making web part easier.

    my $self = shift;

    my $base = $self->config->basedir->subdir( $self->qc_run_id );
    $self->log->debug("base dir: $base");
    #no file in output folder as we don't want this log to show up in the web interface
    #listlatest runs searches output folder, but we actually view error. its weird
    my $out_file = $base->subdir( "error" )->file( 'kill_and_notify.err' );
    $self->log->debug("outfile: $out_file");

    my @cmd = (
        'qc kill-and-notify',
        '--config', $self->config->conffile,
        '--run-id', $self->qc_run_id,
    );

    push @cmd, '--is-lims2' if $self->config->is_lims2;
    push @cmd, '--is-prescreen' if $self->config->is_prescreen;

    my $job_params = {
        out_file => $out_file,
        cmd      => \@cmd,
    };

    $self->log->debug("submitting kill-and-notify job to farm");
    $self->farm_job_runner->submit($job_params);

    #return the job_ids as that is what used to happen.
    $self->log->debug("fetching job id list");
    my $job_id_file = $self->config->basedir->subdir( $self->qc_run_id )->file( "lsf.job_id" );
    my $job_id_list = $self->file_api->get_file_content($job_id_file);
    my @job_ids = split /\n/, $job_id_list;
    return \@job_ids;
}

__PACKAGE__->meta->make_immutable;

1;

__END__
