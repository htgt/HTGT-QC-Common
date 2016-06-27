package HTGT::QC::Action::Misc::KillAndNotify;

use Moose;
use namespace::autoclean;
use IPC::Run qw( run );
use Try::Tiny;

extends qw( HTGT::QC::Action );

override command_names => sub {
    'kill-and-notify'
};

override abstract => sub {
    'kills all bsub processes for a given run'
};

has qc_run_id => (
    is       => 'ro',
    isa      => 'Str',
    traits   => [ 'Getopt' ],
    required => 1,
    cmd_flag => 'run-id',
);

sub execute {
    my ( $self, $opts, $args ) = @_;

    #perhaps we should make sure we have config??

    #the run is being killed, so firstly mark it as failed.
    my $work_dir = $self->config->basedir->subdir( $self->qc_run_id );
    
    my $out_fh = $work_dir->file( 'failed.out' )->openw();
    $out_fh->print( "Running kill and notify, see log file for details.\n" );

    #get all the run ids
    my @job_ids = $work_dir->file( "lsf.job_id" )->slurp( chomp => 1 );

    $self->log->warn( "\nKilling jobs [", join(",", @job_ids), "]\n" );

    if( $self->kill_everything( \@job_ids ) ) {
        #we have succeeded, so create ended.out to identify a run as no longer running
        $work_dir->file( 'ended.out' )->openw->print( "The run was killed successfully.\n" );
    }
    else {
        #this is going into the failed.out file
        $self->log->error( "There was an error killing all the jobs.\n" );
    }
}

sub kill_everything {
    my ( $self, $job_ids ) = @_;

    #kill our bsub tests
    my $kill_output = $self->run_cmd(
        'bkill',
        @{ $job_ids },
    );

    #print $kill_output, "\n";

    #hash to hold all jobs that are still alive
    my %waiting = map { $_ => 1 } @{ $job_ids };

    $self->log->warn( "Waiting for jobs to finish.\n" );

    for ( 0 .. 10 ) {
        #sleep first as it takes a bit of time for them to be killed
        sleep 20; 

        $self->check_if_done( \%waiting );
        
        #see if there's any jobs left in the hash
        if ( keys %waiting ) {
            $self->log->warn( "Still some jobs left alive:\n", join("\n", keys %waiting), "\n" );
        }
        else { 
            $self->log->warn( "All jobs have been killed.\n" );
            return 1;
        }
    }

    #the loop finished so we did not succeed
    return 0;
}

sub check_if_done {
    my ( $self, $waiting ) = @_;

    my $bjobs_output = $self->run_cmd(
        'bjobs',
        #'-G', 'team87-grp', # specifying the group seems to make it say job not found. weird
        keys %{ $waiting } #only get info for the job ids we're interested in
    );

    $self->log->warn( "Bjobs output:\n" . $bjobs_output . "\n" );

    my @lines = split( /\n/, $bjobs_output );

    #example of what we're dealing with here:
    #
    #JOBID   USER    STAT  QUEUE      FROM_HOST   EXEC_HOST   JOB_NAME   SUBMIT_TIME
    #7219712 ds5     RUN   long       farm2-head1 bc-24-1-10  NA12843.sh Dec  4 12:17

    for my $line ( @lines ) {
        next if $line =~ /^JOBID\s+/; #skip the header line if it exists

        #basically replicate awk to extract the job id and status
        my @values = split /\s+/, $line;
        my ( $job_id, $status ) = ( $values[0], $values[2] );

        #farm 3 seems to get rid of jobs immediately from bjobs command, 
        #so if the job isn't found it means it is no longer alive.
        if ( $line =~ /Job <(\d+)> is not found$/ ) {
            $self->log->info( "Job $1 already done."  );
            ( $job_id, $status ) = ( $1, "DONE" ); 
        }

        #check the values are what we expect
        $self->log->warn( "Invalid job id: $job_id (Line: $line)" ) if $job_id !~ /^([0-9]+)$/;
        $self->log->warn( "Invalid status: $status (Line: $line)" ) if $status !~ /^([A-Z]+)$/;
        
        next unless defined $waiting->{ $job_id }; #skip if it has already been deleted

        #if the job has finished remove it from the hash
        if ( $status eq "EXIT" or $status eq "DONE" ) {
            $self->log->warn( "Job $job_id has finished." );
            delete $waiting->{ $job_id };
        }
    }
}

#this should be added to Util::RunCmd
sub run_cmd {
    my ( $self, @cmd ) = @_;

    my $output;

    my $success = run \@cmd, '<', \undef, '>&', \$output; #returns true if zero output
    $self->log->warn( "Command (" . join(" ", @cmd) . ") returned non-zero:\n$output" ) unless $success;

    chomp $output;
    return $output;
}

__PACKAGE__->meta->make_immutable;

1;

__END__
