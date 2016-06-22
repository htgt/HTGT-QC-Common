package HTGT::QC::Util::SubmitQCFarmJob::ESCellPreScreen;

use Moose;
use Try::Tiny;

extends qw( HTGT::QC::Util::SubmitQCFarmJob );

my $QC_CONFIG = $ENV{HTGT_QC_CONF};

#we will only get seq reads for primers in this array
my @valid_primers = ( 'R2R', 'LR', 'LFR' );

#override the MAIN function of SubmitQCFarmJob unlike ESCell and Vector
override 'run_qc_on_farm' => sub {
    my ( $self ) = @_;

    #this is duplicated from the main function but it's only a tiny bit
    my $output_dir = $self->qc_run->workdir->subdir( 'output' );
    my $error_dir = $self->qc_run->workdir->subdir( 'error' ); 
    $self->create_dirs( $output_dir, $error_dir );

    my $stage = $self->qc_run->config->profile( $self->qc_run->profile )->vector_stage;

    my @job_ids;

    #loop seq projs
    try {
        for my $seq_proj ( @{ $self->qc_run->sequencing_projects } ) {
            my $fetch_seq_reads_job_id = $self->fetch_seq_reads( $seq_proj );
            my $align_reads_job_id = $self->align_reads( $fetch_seq_reads_job_id, $seq_proj );
            my $run_analysis_job_id = $self->run_analysis( $align_reads_job_id, $seq_proj );

            #now add them all to our list to be stored in the lsf.job_id file
            push @job_ids, ( $fetch_seq_reads_job_id, $align_reads_job_id, $run_analysis_job_id );
        }

        #do this here. be dependant.
        push @job_ids, $self->persist( @job_ids );
    }
    catch {
        #this is far too subtle of an error in a log no one reads...
        $self->log->warn( "Caught exception creating qc run:\n $_\n" );
    };

    #create lsf.jobs file
    $self->write_job_ids( @job_ids );

    return join "\n", @job_ids;
};

#this is almost the same as in ESCell and Vector,
#here specify a primer filter and dont depend on any other job. 
override 'fetch_seq_reads' => sub {
    my ( $self, $seq_proj ) = @_;

    my ( $out_file, $err_file ) = $self->get_log_filenames( "fetch_seq_reads", $seq_proj );

    my @args = (
        '--output-file', $self->qc_run->workdir->file( "$seq_proj.reads.fasta" ),
        map( { ( '--primer-filter', $_ ) } @valid_primers ), #pass all primers as filters
        $seq_proj
    );

    my @cmd = $self->get_qc_cmd( 'fetch-seq-reads-archive', @args );

    #we send undef as there is no job dependency
    return $self->run_bsub_cmd( undef, $out_file, $err_file, @cmd );
};

#this aligns our sequences to the mouse genome with exonerate
override 'align_reads' => sub {
    my ( $self, $previous_job_id, $seq_proj ) = @_;

    my $exonerate_dir = $self->qc_run->workdir->subdir( 'exonerate' );
    $exonerate_dir->mkpath unless -e $exonerate_dir; 

    my ( $out_file, $err_file ) = $self->get_log_filenames( "align_reads", $seq_proj );

    #exonerate writes to stdout, so we need to move the .out file.
    #by creating this dummy file the .err file will still show up in the latest runs page
    my $out_fh = $out_file->openw();
    $out_fh->print( "To see the actual bsub output go to the exonerate directory.\n" );
    close $out_fh;

    #change output file to be in exonerate directory.
    $out_file = $exonerate_dir->file( "$seq_proj.out" );

    my @args = (
        '--reads', $self->qc_run->workdir->file( "$seq_proj.reads.fasta" )
    );

    my @cmd = $self->get_qc_cmd( 'align-reads-genome', @args );

    return $self->run_bsub_cmd( $previous_job_id, $out_file, $err_file, @cmd );
};

#this step creates the final yaml that we will display to the user
override 'run_analysis' => sub {
    my ( $self, $previous_job_id, $seq_proj ) = @_; 

    my ( $out_file, $err_file ) = $self->get_log_filenames( "run_analysis", $seq_proj );

    my @args = (
        '--seq-reads', $self->qc_run->workdir->file( "$seq_proj.reads.fasta" ),
        '--output-file', $self->qc_run->workdir->file( 'prescreen', "$seq_proj.prescreen.yaml" ),
        '--alignments', $self->qc_run->workdir->file( 'exonerate', "$seq_proj.out" )
    );

    my @cmd = $self->get_qc_cmd( 'run-pre-screen-analysis', @args );

    return $self->run_bsub_cmd( $previous_job_id, $out_file, $err_file, @cmd );
};

override 'persist' => sub {
    my ( $self, @previous_job_ids ) = @_;

    my ( $out_file, $err_file ) = $self->get_log_filenames( "persist_htgt" );

    #create bsub dependancy. make it a proper function inside SubmitQCFarmJob
    #as its now needed twice.
    #USE HANDY NEW BSUB OPTION

    my @args = (
        '--analysis-dir', $self->qc_run->workdir->subdir( 'prescreen' ),
        '--run-id', $self->qc_run->id,
        '--commit',
    );

    my @cmd = $self->get_qc_cmd( 'persist-prescreen-htgtdb', @args );

    return $self->run_bsub_cmd( \@previous_job_ids, $out_file, $err_file, @cmd );
};

1;
