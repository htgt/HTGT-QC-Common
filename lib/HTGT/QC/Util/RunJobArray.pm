package HTGT::QC::Util::RunJobArray;

use strict;
use warnings FATAL => 'all';

use Sub::Exporter -setup => {
    exports => [ 'run_job_array' ],
    groups  => {
        default => [ 'run_job_array' ]
    }
};

use Path::Class;
use IPC::System::Simple qw( capturex );
use Log::Log4perl ':easy';
use Try::Tiny;
use HTGT::QC::Exception;
use HTGT::QC::Util::Which;
use YAML::Any;

my @BSUB               = ( which( 'bsub' ), qw( -P team87 -q normal ) );
my $JOB_SUBMITTED_RX   = qr/^Job <(\d+)> is submitted to queue <.+>/;
#const my $NO_MATCHING_JOB_RX => qr/No matching job found. Job not submitted./;

sub run_job_array {
    my ( $work_dir, $commands ) = @_;

    $work_dir = dir( $work_dir );

    my $job_id = run_bsub_and_wait( $work_dir, $commands );

    ensure_successfully_completed( $job_id, scalar( @{$commands} ), $work_dir );
    
    return $job_id;
}

sub run_bsub_and_wait {
    my ( $work_dir, $commands ) = @_;
    
    my $cmd_file = write_commands( $work_dir, $commands );

    my $jobspec = sprintf 'qc[1-%d]', scalar @{$commands};

    my @bsub_job_array = ( @BSUB,
                           '-o', $work_dir->file( '%J.%I.out' ),
                           '-J', $jobspec,
                           'perl', '-MYAML::Any', '-e', 'exec YAML::Any::LoadFile(shift)->[$ENV{LSB_JOB_INDEX} - 1]',
                           $cmd_file );

    DEBUG( 'Submitting job array' );
    my $res = capturex( @bsub_job_array );
    INFO( $_ ) for split /\n/, $res;
    my ( $job_id ) = $res =~ m/$JOB_SUBMITTED_RX/
        or HTGT::QC::Exception->throw( message => "unexpected return from bsub: $res" );
    
    my @bsub_wait = ( @BSUB,
                      '-i', '/dev/null',
                      '-o', '/dev/null',
                      '-w', sprintf( 'ended(%d)', $job_id ),
                      '-K',
                      '/bin/true' );

    my $done;
    my $n_attempts = 3;

    DEBUG( 'Waiting for job array to complete' );
    while ( $n_attempts-- and not $done ) {
        try {
            my $res = capturex( @bsub_wait );
            INFO( $_ ) for split /\n/, $res;
            $done = 1;
        } catch {
            ERROR( $_ );
            sleep 2**(3 - $n_attempts);
        };
    }

    HTGT::QC::Exception->throw( message => "Failed to wait for job array to complete" )
            unless $done;

    return $job_id;
}

sub ensure_successfully_completed {
    my ( $job_id, $num_jobs, $outdir ) = @_;

    my $num_failed = 0;
    
    for my $job_num ( 1..$num_jobs) {
        my $out_file = $outdir->file( "$job_id.$job_num.out" );
        DEBUG( "Reading $out_file" );
        my $is_success;
        my $fh = $out_file->openr;
        while ( ! $fh->eof ) {
            my $line = $fh->getline;
            if ( $line =~ m/^Successfully completed\.$/ ) {
                DEBUG( "$job_num completed OK" );
                $is_success = 1;
                last;
            }
        }
        $num_failed++ unless $is_success;
    }

    if ( $num_failed > 0 ) {
        HTGT::QC::Exception->throw(
            "$num_failed of $num_jobs exonerate jobs failed to complete successfully"
        );
    }
}


1;

__END__
