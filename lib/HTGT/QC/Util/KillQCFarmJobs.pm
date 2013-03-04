package HTGT::QC::Util::KillQCFarmJobs;

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

sub kill_unfinished_farm_jobs {
    #bsub qc kill-and-notify --config file --run-id FD0C-... 
    #essentially, like before, just a handy wrapper for bsubbing the kills
    #making web part easier.

    my $self = shift;

    my $base = $self->config->basedir->subdir( $self->qc_run_id );
    #no file in output folder as we don't want this log to show up in the web interface
    #listlatest runs searches output folder, but we actually view error. its weird
    my $out_file = $base->subdir( "error" )->file( 'kill_and_notify.err' );

    my @cmd = (
        'bsub',
        '-G', 'team87-grp',
        '-o', $out_file,
        '-M', '500000', #we were running out of memory for some reason
        '-R', '"select[mem>500] rusage[mem=500]"',
        'qc kill-and-notify',
        '--config', $self->config->conffile,
        '--run-id', $self->qc_run_id,
    );

    push @cmd, '--is-lims2' if $self->config->is_lims2;
    push @cmd, '--is-prescreen' if $self->config->is_prescreen;

    $self->run_cmd( @cmd );

    #return the job_ids as that is what used to happen.
    my @job_ids = $self->config->basedir->subdir( $self->qc_run_id )->file( "lsf.job_id" )->slurp( chomp => 1);
    return \@job_ids;
}

sub run_cmd {
    my ( $self, @cmd ) = @_;

    my $output;
    ## no critic (RequireCheckingReturnValueOfEval)
    eval {
        IPC::Run::run( \@cmd, '<', \undef, '>&', \$output )
                or die "$output\n";
    };
    if ( my $err = $@ ) {
        chomp $err;
        #don't die here as it mostly comes back as failed
        print "Command returned non-zero\n: $err";
    }
    ## use critic

    chomp $output;
    return  $output;
}
__PACKAGE__->meta->make_immutable;

1;

__END__
