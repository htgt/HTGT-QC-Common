package HTGT::QC::Util::RunCmd;

use strict;
use warnings FATAL => 'all';

use Sub::Exporter -setup => {
    exports => [ 'run_cmd', 'run_bsub_cmd' ],
    groups  => {
        default => [ 'run_cmd', 'run_bsub_cmd' ]
    }
};

#
#these need to be added into SubmitQCFarmJob
#

#should also use Try::tiny here instead of a non-localised $@
sub run_cmd {
    my ( @cmd ) = @_;

    my $output;
    
    eval {
        IPC::Run::run( \@cmd, '<', \undef, '>&', \$output )
                or die "$output\n";
    };
    if ( my $err = $@ ) {
        chomp $err; #WE put in the \n why are we chomping??
        die "Command failed: $err";
    }

    chomp $output;
    return $output;
}

#NOTE: the order of @_ in this function is different to that in SubmitQCFarmJob
sub run_bsub_cmd {
    my ( $out_file, $err_file, $memory_required, $previous_job_id, @cmd ) = @_;

    #if you make a change to this command DON'T forget that
    #post-filter in ESCell has its own bsub function, which you may also want to change.

    #raise exception if we dont have the required items, otherwise everything would break
    HTGT::QC::Exception->throw( message => "Not enough parameters passed to run_bsub_cmd" ) 
        unless ( $out_file and $err_file and @cmd );

    #default memory required to 2000
    $memory_required = 2000 unless $memory_required;
#    my $memory_limit = $memory_required * 1000; #farm -M is weird and not in MB or GB.
    my $memory_limit = $memory_required; 

    my @bsub = (
        'bsub',
        '-q', 'normal',
        '-o', $out_file,
        '-e', $err_file,
        '-M', $memory_limit,
        '-R', 'select[mem>' . $memory_required . '] rusage[mem=' . $memory_required . ']',
    );

    #allow the user to specify multiple job ids by providing an array ref.
    #also allow NO dependency by havign previous_job_id as undef or 0
    if ( ref $previous_job_id eq 'ARRAY' ) {
        #this makes -w 'done(1) && done(2) && ...'
        push @bsub, ( '-w', join( " && ", map { 'done(' . $_ . ')' } @{ $previous_job_id } ) );
    }
    elsif ( $previous_job_id ) {
        push @bsub, ( '-w', 'done(' . $previous_job_id . ')' );
    }

    push @bsub, @cmd; #anything left is the actual command

    my $output = run_cmd( @bsub );
    my ( $job_id ) = $output =~ /Job <(\d+)>/;

    return $job_id;
}

1;

__END__
