package HTGT::QC::Util::SubmitQCFarmJob;

use Moose;
use Moose::Util::TypeConstraints;
use IPC::Run ();
use HTGT::QC::Exception;
use namespace::autoclean;
use Path::Class qw( dir file );

with 'MooseX::Log::Log4perl';

has qc_run => (
    is       => 'ro',
    isa      => 'HTGT::QC::Run',
    required => 1
);

#allow user to specify if they need more memory
has memory_required => (
    is       => 'rw',
    isa      => subtype( 'Int' => where { $_ > 100 && $_ < 16000 } ),
    default  => 2000,
);

my $QC_CONFIG = $ENV{HTGT_QC_CONF};

#if you override this you will have to create the output/error directories
#and run write_job_ids.
sub run_qc_on_farm {
    my ( $self ) = @_;

    my $output_dir = $self->qc_run->workdir->subdir( 'output' );
    my $error_dir = $self->qc_run->workdir->subdir( 'error' );
    $self->create_dirs( $output_dir, $error_dir );

    my $stage = $self->qc_run->config->profile( $self->qc_run->profile )->vector_stage;
    my $fetch_template_job_id = $self->fetch_template_data( $stage );
    my $write_eng_seqs_job_id = $self->write_eng_seqs( $fetch_template_job_id );

    #this function is implemented by the subclass so they have flexibility over this section
    my $additional_job_ids = $self->_run_qc_on_farm( $write_eng_seqs_job_id );
    
    #last item in additional job ids is the post filter job id, which is waiting
    #for ALL the other additional job ids to finish. they are in \n separated list
    my $post_filter_job_id = ( split /\n/, $additional_job_ids )[ -1 ];
    my $generate_report_job_id = $self->generate_report( $post_filter_job_id );
    my $persist_job_id = $self->persist( $generate_report_job_id, $stage );

    #this will return a \n separated list just like _run_qc_on_farm
    my $final_job_ids = $self->_final_steps( $persist_job_id );

    $self->write_job_ids(
        $fetch_template_job_id, 
        $write_eng_seqs_job_id, 
        $additional_job_ids, 
        $post_filter_job_id, 
        $generate_report_job_id, 
        $persist_job_id,
        $final_job_ids,
    );
}

sub write_job_ids {
    my ( $self, @job_ids ) = @_;

    my $job_id_log = $self->qc_run->workdir->file( "lsf.job_id" );
    my $job_id_log_fh = $job_id_log->openw();
    
    $job_id_log_fh->print( join( "\n", @job_ids ) );
}

sub create_dirs {
    my ( $self, @dirs ) = @_;

    for my $dir( @dirs ){
        -d $dir
            or $dir->mkpath
                or HTGT::QC::Exception->throw( message => "Failed to create directory $dir: $!" );
    }

    return;
}

#all the steps implemented here are the same for vector and es cell runs.
sub fetch_template_data {
    my ( $self, $stage ) = @_;

    my ( $out_file, $err_file ) = $self->get_log_filenames( "fetch_template" );

    my @args = ( '--output-file', $self->qc_run->workdir->file( 'template.yaml' ) );

    #lims2 doesnt accept a stage
    push @args, ( '--stage', $stage ) unless $self->qc_run->config->is_lims2;
    push @args, $self->qc_run->template_plate;

    #the commands are only slightly different for htgt and lims2
    my $qc_cmd = 'fetch-template-data-' . ( ( $self->qc_run->config->is_lims2 ) ? 'lims2' : 'htgt' );

    my @cmd = $self->get_qc_cmd( $qc_cmd, @args );

    #there is no previous_job_id so send undef to specify no dependency 
    return $self->run_bsub_cmd( undef, $out_file, $err_file, @cmd );
}

sub write_eng_seqs {
    my ( $self, $previous_job_id ) = @_;

    my ( $out_file, $err_file ) = $self->get_log_filenames( "write_eng_seqs" );

    my @args = (
        '--output-dir', $self->qc_run->workdir->subdir( 'eng_seqs' ),
        $self->qc_run->workdir->file( 'template.yaml' )
    );

    my @cmd = $self->get_qc_cmd( 'write-eng-seqs', @args );

    return $self->run_bsub_cmd( $previous_job_id, $out_file, $err_file, @cmd );
}

sub generate_report {
    my ( $self, $previous_job_id ) = @_;

    my ( $out_file, $err_file ) = $self->get_log_filenames( "generate_report" );

    my @args = (
        '--analysis', $self->qc_run->workdir->subdir( 'post-filter' ),
        '--output-file', $self->qc_run->workdir->file( 'report.csv' )
    );

    my @cmd = $self->get_qc_cmd( 'generate-report-full', @args );

    return $self->run_bsub_cmd( $previous_job_id, $out_file, $err_file, @cmd );
}

sub persist {
    my ( $self, $previous_job_id, $stage ) = @_;

    HTGT::QC::Exception->throw( "persist requires a job id and stage." )
        unless ( $previous_job_id and $stage );

    if( $self->qc_run->config->is_lims2 ) {
        return $self->persist_lims2( $previous_job_id, $stage );
    }
    else {
        return $self->persist_htgt( $previous_job_id, $stage );
    }
}

#the only thing that changes in the persist steps between es cell and vector is that 
#there are multiple seq_reads for es cell. The get_seq_read_files method handles this.
sub persist_htgt {
    my ( $self, $previous_job_id, $stage ) = @_;

    my ( $out_file, $err_file ) = $self->get_log_filenames( "persist_htgt" );

    my @args = (
        '--run-id', $self->qc_run->id,
        '--template-plate', $self->qc_run->template_plate,
        $self->get_sequencing_projects,
        $self->get_seq_read_files,
        '--analysis-dir', $self->qc_run->workdir->subdir( 'post-filter' ),
        '--eng-seqs', $self->qc_run->workdir->subdir( 'eng_seqs' ),
        '--stage', $stage,
        '--commit'
    );

    my @cmd = $self->get_qc_cmd( 'persist-htgtdb', @args );

    return $self->run_bsub_cmd( $previous_job_id, $out_file, $err_file, @cmd );
}

sub persist_lims2 {
    my ( $self, $previous_job_id, $stage ) = @_;

    # There are several steps to persist lims2 qc info to db
    my $persist_qc_run_id = $self->persist_lims2_qc_run( $previous_job_id );
    my $persist_seq_reads_id = $self->persist_lims2_seq_reads( $persist_qc_run_id );
    my $persist_test_results_id = $self->persist_lims2_test_results( $persist_seq_reads_id);

    return join "\n", $persist_qc_run_id, $persist_seq_reads_id, $persist_test_results_id; 
}

sub persist_lims2_qc_run {
    my ( $self, $previous_job_id )= @_;

    my ( $out_file, $err_file ) = $self->get_log_filenames( "persist_lims2_qc_run" );

    my @args = (
        '--run-id', $self->qc_run->id,
        $self->get_sequencing_projects,
        '--analysis-dir', $self->qc_run->workdir->subdir( 'post-filter' ),
        '--lims2-template-file', $self->qc_run->workdir->file( 'template.yaml' ),
        '--created-by', $self->qc_run->created_by,
        '--species', $self->qc_run->species
    );

    my @cmd = $self->get_qc_cmd( 'persist-lims2-qc-run', @args );

    return $self->run_bsub_cmd( $previous_job_id, $out_file, $err_file, @cmd );
}


sub persist_lims2_seq_reads {
    my ( $self, $previous_job_id ) = @_;

    my ( $out_file, $err_file ) = $self->get_log_filenames( "persist_lims2_seq_reads" );

    #analysis-dir is only used by test-results NOT seq-reads or qc-run.

    my %plate_map = %{ $self->qc_run->plate_map };

    my @plate_maps;
    for my $map_key ( keys %plate_map ){
        push @plate_maps, '--plate-map';
        push @plate_maps, $map_key . '=' . $plate_map{ $map_key };
    }

    my @args = (
        '--run-id', $self->qc_run->id,
        '--analysis-dir', $self->qc_run->workdir->subdir( 'post-filter' ),
        $self->get_sequencing_projects,
        $self->get_seq_read_files,
        '--species', $self->qc_run->species,
        @plate_maps #this is empty if its es cell so we can just ignore it
    );

    my @cmd = $self->get_qc_cmd( 'persist-lims2-seq-reads', @args );

    return $self->run_bsub_cmd( $previous_job_id, $out_file, $err_file, @cmd );
}

sub persist_lims2_test_results {
    my ( $self, $previous_job_id ) = @_;

    my ( $out_file, $err_file ) = $self->get_log_filenames( "persist_lims2_test_results" );

    my @args = (
        '--run-id', $self->qc_run->id,
        '--analysis-dir', $self->qc_run->workdir->subdir( 'post-filter' ),
    );

    my @cmd = $self->get_qc_cmd( 'persist-lims2-test-results', @args );

    return $self->run_bsub_cmd( $previous_job_id, $out_file, $err_file, @cmd );
}

#
#these methods must be implemented in a subclass.
#unless you override run_qc_on_farm, in which case go wild.
#

sub _run_qc_on_farm {
    confess "_run_qc_on_farm must be overriden by a subclass.";
}
sub fetch_seq_reads {
    confess "fetch_seq_reads should be overriden by a subclass.";
}
sub align_reads {
    confess "align_reads should be overriden by a subclass.";
}
sub pre_filter {
    confess "pre_filter should be overriden by a subclass.";
}
sub run_analysis {
    confess "run_analysis should be overriden by a subclass.";
}
sub post_filter {
    confess "post_filter should be overriden by a subclass.";
}
sub _final_steps {
    return ""; #this one is optional; its just in case a sub class wants to run something at the end
}
sub get_seq_read_files {
    confess "get_seq_read_files should be overriden by a subclass.";
}

#
#helper functions 
#

sub get_sequencing_projects {
    my ( $self ) = @_;
    #used by persist steps to pass all sequencing projects to qc
    my @sequencing_projects;
    for my $sp ( @{ $self->qc_run->sequencing_projects } ){
        push @sequencing_projects, '--sequencing-project';
        push @sequencing_projects, $sp;
    }

    return @sequencing_projects;
}

#this code was duplicated at every stage, so this is just for conciseness really.
sub get_log_filenames {
    my ( $self, $name, $seq_proj ) = @_;

    my $out_file = $self->qc_run->workdir->file( 'output', ( $seq_proj ? "$seq_proj." : '' ) . $name . '.out' );
    my $err_file = $self->qc_run->workdir->file( 'error',  ( $seq_proj ? "$seq_proj." : '' ) . $name . '.err' );

    return $out_file, $err_file;
}

#returns a list containing a user specified qc command and arguments, with
#the intenion of being given to IPC::Run
sub get_qc_cmd {
    my ( $self, $qc_cmd, @args ) = @_;

    #we expect the qc command that is to be run, otherwise we raise an exception
    HTGT::QC::Exception->throw( message => "No QC command specified" ) unless $qc_cmd;

    #add in the qc args requried by every command, then add the cmd specific args
    my @cmd = (        
        'qc', $qc_cmd,
        '--debug',
        '--config', $ENV{NFS_HTGT_QC_CONF},
        '--profile', $self->qc_run->profile,
        @args
    );

    push @cmd, '--is-lims2' if $self->qc_run->config->is_lims2;

    return @cmd;
}

#set all common options for bsub and run the user specified command. 
sub run_bsub_cmd {
    my ( $self, $previous_job_id, $out_file, $err_file, @cmd ) = @_;

    #if you make a change to this command you'll need to find all places bsub is used,
    #as not everyone uses this.

    #raise exception if we dont have the required items, otherwise everything would break
    HTGT::QC::Exception->throw( message => "Not enough parameters passed to run_bsub_cmd" ) 
        unless ( $out_file and $err_file and @cmd );

    my $memory_limit = $self->memory_required; # no factors required for farm3

    my @bsub = (
        'bsub',
        '-q', 'normal',
        '-o', $out_file,
        '-e', $err_file,
        '-M', $memory_limit,
        '-R', 'select[mem>' . $self->memory_required . '] rusage[mem=' . $self->memory_required . ']',
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

    my $output = $self->run_cmd( @bsub );
    my ( $job_id ) = $output =~ /Job <(\d+)>/;

    return $job_id;
}

#this should be removed and Util::RunCmd used for consistency 
sub run_cmd {
    my ( $self, @cmd ) = @_;

    my $output;
    
    eval {
        IPC::Run::run( \@cmd, '<', \undef, '>&', \$output )
                or die "$output\n";
    };
    if ( my $err = $@ ) {
        chomp $err;
        die "Command failed: $err";
    }

    chomp $output;
    return  $output;
}

__PACKAGE__->meta->make_immutable;

1;

__END__
