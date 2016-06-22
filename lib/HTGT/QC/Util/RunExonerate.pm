package HTGT::QC::Util::RunExonerate;

use strict;
use warnings FATAL => 'all';

use Sub::Exporter -setup => {
    exports => [ 'run_exonerate' ],
    groups  => {
        default => [ 'run_exonerate' ]
    }
};

use Path::Class;
use IPC::System::Simple qw( capturex );
use Log::Log4perl ':easy';
use Try::Tiny;
use HTGT::QC::Exception;
use HTGT::QC::Util::Which;

my $RUN_EXONERATE = which( 'run-exonerate-jobarray.pl' );
my @BSUB          = ( which( 'bsub' ), qw( -q normal ) );

my $JOB_SUBMITTED_RX   = qr/Job <(\d+)> is submitted to queue <.+>/;
#const my $NO_MATCHING_JOB_RX => qr/No matching job found. Job not submitted./;

sub run_exonerate {
    my ( $seq_reads, $syn_vecs, $outdir, $model ) = @_;

    $model = 'ungapped' unless defined $model;
    
    $outdir = dir( $outdir );

    my $job_id = run_bsub_and_wait( $seq_reads, $syn_vecs, $outdir, $model );

    ensure_successfully_completed( $job_id, scalar( @{$syn_vecs} ), $outdir );
    
    return $job_id;
}

sub run_bsub_and_wait {
    my ( $query, $targets, $outdir, $model ) = @_;
    
    my $jobspec = sprintf 'qc[1-%d]', scalar @{$targets};

    my @bsub_job_array = ( @BSUB,
                           "-R'select[mem>2000] rusage[mem=2000]'", '-M2000',
                           '-o', $outdir->file( '%J.%I.out' ),
                           '-J', $jobspec,
                           $RUN_EXONERATE, $model, $query, @{$targets} );

    WARN( "Submitting job array @bsub_job_array" );
    my $res = capturex( @bsub_job_array );
    INFO( $_ ) for split /\n/, $res;
    my ( $job_id ) = $res =~ m/$JOB_SUBMITTED_RX/
        or HTGT::QC::Exception->throw( message => "unexpected return from bsub: $res" );
    
    my @bsub_wait = ( @BSUB,
                      '-i', '/dev/null',
                      '-o', '/dev/null',
                      "-R 'select[mem>100] rusage[mem=100]'", '-M 100',
                      '-w', sprintf( 'ended(%d)', $job_id ),
                      '-K',
                      '/bin/true' );
    WARN( "Running bsub command:\n" . join(" ", @bsub_wait) );

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
            if ( $line =~ m/^Successfully completed\.?$/ ) {
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
