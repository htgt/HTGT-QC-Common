package HTGT::QC::Util::SubmitQCFarmJob::Vector;

use Moose;
extends qw( HTGT::QC::Util::SubmitQCFarmJob );

my $QC_CONFIG = $ENV{HTGT_QC_CONF};

override '_run_qc_on_farm' => sub {
    my ( $self, $write_eng_seqs_job_id ) = @_;

    my $fetch_seq_reads_job_id = $self->fetch_seq_reads( $write_eng_seqs_job_id );
    my $align_reads_job_id = $self->align_reads( $fetch_seq_reads_job_id );
    my $pre_filter_job_id = $self->pre_filter( $align_reads_job_id );
    my $run_analysis_job_id = $self->run_analysis( $pre_filter_job_id );
    my $post_filter_job_id = $self->post_filter( $run_analysis_job_id );

    return join "\n", $fetch_seq_reads_job_id, 
                      $align_reads_job_id, 
                      $pre_filter_job_id, 
                      $run_analysis_job_id, 
                      $post_filter_job_id;
};

override 'fetch_seq_reads' => sub {
    my ( $self, $previous_job_id ) = @_;

    my ( $out_file, $err_file ) = $self->get_log_filenames( "fetch_seq_reads" );

    my @args = (
        '--output-file', $self->qc_run->workdir->file( 'reads.fasta' ),
        @{ $self->qc_run->sequencing_projects }
    );

    my @cmd = $self->get_qc_cmd( 'fetch-seq-reads-archive', @args );

    return $self->run_bsub_cmd( $previous_job_id, $out_file, $err_file, @cmd );
};

override 'align_reads' => sub {
    my ( $self, $previous_job_id ) = @_;

    my ( $out_file, $err_file ) = $self->get_log_filenames( "align_reads" );

    my @args = (
        '--reads',      $self->qc_run->workdir->file( 'reads.fasta' ),
        '--output-dir', $self->qc_run->workdir->subdir( 'exonerate' ),
        $self->qc_run->workdir->subdir( 'eng_seqs' ) . '/*.fasta'
    );

    my @cmd = $self->get_qc_cmd( 'align-reads-exonerate', @args );

    return $self->run_bsub_cmd( $previous_job_id, $out_file, $err_file, @cmd );
};

override 'pre_filter' => sub {
    my ( $self, $previous_job_id ) = @_;

    #make the memory for pre filter double whatever was set.
    $self->memory_required( $self->memory_required * 2 );

    my ( $out_file, $err_file ) = $self->get_log_filenames( "pre_filter" );

    my %plate_map = %{ $self->qc_run->plate_map };

    my @plate_maps;
    for my $map_key ( keys %plate_map ) {
        push @plate_maps, '--plate-map';
        push @plate_maps, $map_key . '=' . $plate_map{ $map_key };
    }

    my @args = (
        '--output-file', $self->qc_run->workdir->file( 'alignments.yaml' ),
        @plate_maps,
        $self->qc_run->workdir->subdir( 'exonerate' ) . '/*.out'
    );

    my @cmd = $self->get_qc_cmd( 'pre-filter-score', @args );

    my $job_id = $self->run_bsub_cmd( $previous_job_id, $out_file, $err_file, @cmd );

    #return the memory required to what it was before as only pre filter needs more.
    $self->memory_required( $self->memory_required / 2 );

    return $job_id;
};

override 'run_analysis' => sub {
    my ( $self, $previous_job_id ) = @_;

    my ( $out_file, $err_file ) = $self->get_log_filenames( "run_analysis" );

    my @args = (
        '--seq-reads', $self->qc_run->workdir->file( 'reads.fasta' ),
        '--output-dir', $self->qc_run->workdir->subdir( 'analysis' ),
        '--eng-seqs', $self->qc_run->workdir ->subdir( 'eng_seqs' ),
        '--template-params', $self->qc_run->workdir->file( 'template.yaml' ),
        $self->qc_run->workdir->file( 'alignments.yaml' )
    );

    my @cmd = $self->get_qc_cmd( 'run-analysis', @args );

    return $self->run_bsub_cmd( $previous_job_id, $out_file, $err_file, @cmd );
};

override 'post_filter' => sub {
    my ( $self, $previous_job_id ) = @_;

    my ( $out_file, $err_file ) = $self->get_log_filenames( "post_filter" );

    my @args = (
        '--output-dir', $self->qc_run->workdir->subdir( 'post-filter' ),
        $self->qc_run->workdir->subdir( 'analysis' )
    );

    my @cmd = $self->get_qc_cmd( 'post-filter-num-primers', @args );

    return $self->run_bsub_cmd( $previous_job_id, $out_file, $err_file, @cmd );
};

#we only have 1 seq read (unlike es cell)
override 'get_seq_read_files' => sub {
    my ( $self ) = @_;

    return '--seq-reads', $self->qc_run->workdir->file( 'reads.fasta' );
};

1;
