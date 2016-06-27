package HTGT::QC::Util::SubmitQCFarmJob::ESCell;

use Moose;
use Try::Tiny;
use List::MoreUtils qw( uniq );

extends qw( HTGT::QC::Util::SubmitQCFarmJob );

my $QC_CONFIG = $ENV{HTGT_QC_CONF};

override '_run_qc_on_farm' => sub {
    my ( $self, $write_eng_seqs_job_id ) = @_;

    #we have a try catch in case a bsub fails, as otherwise no job ids are returned
    #and the jobs that did succeed cant be killed.
    
    my ( @job_ids, @run_analysis_job_ids );
    try {
        for my $seq_proj ( @{ $self->qc_run->sequencing_projects } ) {
            my $fetch_seq_reads_job_id = $self->fetch_seq_reads( $write_eng_seqs_job_id, $seq_proj );
            my $align_reads_job_id = $self->align_reads( $fetch_seq_reads_job_id, $seq_proj );
            my $pre_filter_job_id = $self->pre_filter( $align_reads_job_id, $seq_proj );
            my $run_analysis_job_id = $self->run_analysis( $pre_filter_job_id, $seq_proj );

            #now add them all to our list to be stored in the lsf.job_id file
            push @job_ids, ( $fetch_seq_reads_job_id, $align_reads_job_id, $pre_filter_job_id, $run_analysis_job_id );

            #we use this for dependencies as it signifies when each individual sequencing project has finished.
            push @run_analysis_job_ids, $run_analysis_job_id;  
        }

        #post filter must wait for ALL the sets of jobs to finish, so needs all the different job ids
        push @job_ids, $self->post_filter( @run_analysis_job_ids );
    }
    catch {
        #this is far too subtle
        $self->log->error( "Caught exception creating qc run:\n $_" );
    };

    return join "\n", @job_ids;
};

override 'fetch_seq_reads' => sub {
    my ( $self, $previous_job_id, $seq_proj ) = @_;

    #we're gonna have a LOT of logs
    #how should they be displayed on the qc page?
    my ( $out_file, $err_file ) = $self->get_log_filenames( "fetch_seq_reads", $seq_proj );

    my @args = (
        '--output-file', $self->qc_run->workdir->file( "$seq_proj.reads.fasta" ),
        $seq_proj
    );

    my @cmd = $self->get_qc_cmd( 'fetch-seq-reads-archive', @args );

    return $self->run_bsub_cmd( $previous_job_id, $out_file, $err_file, @cmd );
};

override 'align_reads' => sub {
    my ( $self, $previous_job_id, $seq_proj ) = @_;

    my ( $out_file, $err_file ) = $self->get_log_filenames( "align_reads", $seq_proj );

    my @args = (
        '--reads',      $self->qc_run->workdir->file( "$seq_proj.reads.fasta" ),
        '--output-dir', $self->qc_run->workdir->subdir( "$seq_proj.exonerate" ),
        $self->qc_run->workdir->subdir( 'eng_seqs' ) . '/*.fasta'
    );

    my @cmd = $self->get_qc_cmd( 'align-reads-exonerate', @args );

    return $self->run_bsub_cmd( $previous_job_id, $out_file, $err_file, @cmd );
};

override 'pre_filter' => sub {
    my ( $self, $previous_job_id, $seq_proj ) = @_;

    my ( $out_file, $err_file ) = $self->get_log_filenames( "pre_filter", $seq_proj );

    #no plate maps

    my @args = (
        '--output-file', $self->qc_run->workdir->file( "$seq_proj.alignments.yaml" ),
        $self->qc_run->workdir->subdir( "$seq_proj.exonerate" ) . '/*.out'
    );

    my @cmd = $self->get_qc_cmd( 'pre-filter-score', @args );

    return $self->run_bsub_cmd( $previous_job_id, $out_file, $err_file, @cmd );
};

override 'run_analysis' => sub {
    my ( $self, $previous_job_id, $seq_proj ) = @_;

    my ( $out_file, $err_file ) = $self->get_log_filenames( "run_analysis", $seq_proj );

    my @args = (
        '--seq-reads',  $self->qc_run->workdir->file( "$seq_proj.reads.fasta" ),
        '--output-dir', $self->qc_run->workdir->subdir( "$seq_proj.analysis" ),
        '--eng-seqs', $self->qc_run->workdir->subdir( 'eng_seqs' ),
        '--template-params', $self->qc_run->workdir->file( 'template.yaml' ),
        $self->qc_run->workdir->file( "$seq_proj.alignments.yaml" )
    );

    my @cmd = $self->get_qc_cmd( 'run-analysis', @args );

    return $self->run_bsub_cmd( $previous_job_id, $out_file, $err_file, @cmd );
};

override 'post_filter' => sub {
    my ( $self, @previous_job_ids ) = @_;

    my ( $out_file, $err_file ) = $self->get_log_filenames( "post_filter" );

    #post-filter is only run once, so needs ALL the analysis files we generated
    my @analysis_files;
    for my $sp ( @{ $self->qc_run->sequencing_projects } ) {
        push @analysis_files, $self->qc_run->workdir->subdir( "$sp.analysis" );
    }

    my @args = (
        '--output-dir', $self->qc_run->workdir->subdir( 'post-filter' ),
        @analysis_files
    );

    my @cmd = $self->get_qc_cmd( 'post-filter-es-cell', @args );

    #give bsub MULTIPLE dependencies as we want to wait for all the other jobs to finish first.
    return $self->run_bsub_cmd( \@previous_job_ids, $out_file, $err_file, @cmd );
};

override '_final_steps' => sub {
    my ( $self, $persist_job_id ) = @_;

    if( $self->qc_run->config->is_lims2 ) {
        return;
    }
    #get a list of all the actual plate names by stripping trailing character
    #for example, HEPD0848_1_R -> HEPD0848_1
    my @all_plates = uniq( map { $_ =~ /(\w+_\d{1,2})_\w$/ } @{ $self->qc_run->sequencing_projects } );

    #now for each plate run update-escell-plate-qc, and keep all the job_ids
    my @job_ids;
    for my $plate ( @all_plates ) {
        my ( $out_file, $err_file ) = $self->get_log_filenames( "update_plates_" . $plate );

        my @cmd = (
            'update-escell-plate-qc.pl',
            '--orig-plate-name', $plate, #currently no way for a user to choose this.
            '--plate-name', $plate,
            '--qc-run-id', $self->qc_run->id, 
            '--user-id', 'qc'
        );

        push @job_ids, $self->run_bsub_cmd( $persist_job_id, $out_file, $err_file, @cmd );
    }

    return join "\n", @job_ids;
};

#es-cell runs have multiple seq reads, and persist needs to know about all of them.
override 'get_seq_read_files' => sub {
    my ( $self ) = @_;

    my @seq_reads;
    for my $seq_proj ( @{ $self->qc_run->sequencing_projects } ) {
        push @seq_reads, ( '--seq-reads', $self->qc_run->workdir->file( "$seq_proj.reads.fasta" ) );
    }
    return @seq_reads;
};

1;
