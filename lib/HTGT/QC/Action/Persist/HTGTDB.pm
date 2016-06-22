package HTGT::QC::Action::Persist::HTGTDB;

use Moose;
use Digest::SHA1 qw( sha1_hex );
use Bio::SeqIO;
use HTGT::DBFactory;
use List::Util qw( sum );
use YAML::Any;
use namespace::autoclean;

extends qw( HTGT::QC::Action::Persist );
with qw( HTGT::QC::Util::SeqReads );

override command_names => sub {
    'persist-htgtdb'
};

override abstract => sub {
    'persist test results to HTGT database'
};

has schema => (
    is      => 'ro',
    isa     => 'HTGTDB',
    default => sub { HTGT::DBFactory->connect( 'eucomm_vector' ) }
);

has sequencing_projects => (
    isa      => 'ArrayRef[Str]',
    traits   => [ 'Getopt', 'Array' ],
    cmd_flag => 'sequencing-project',
    required => 1,
    handles  => {
        sequencing_projects => 'elements'
    }
);        

has vector_stage => (
    is         => 'ro',
    isa        => 'Str',
    traits     => [ 'Getopt' ],
    cmd_flag   => 'stage',
    required   => 1
);

has eng_seqs_dir => (
    is       => 'ro',
    isa      => 'Path::Class::Dir',
    traits   => [ 'Getopt' ],
    cmd_flag => 'eng-seqs',
    coerce   => 1,
    required => 1
);

has template_plate_name => (
    is       => 'ro',
    isa      => 'Str',
    traits   => [ 'Getopt' ],
    cmd_flag => 'template-plate',
    required => 1
);

has commit => (
    is      => 'ro',
    isa     => 'Bool',
    traits  => [ 'Getopt' ],
    default => 0
);

sub execute {
    my ( $self, $opts, $args ) = @_;
    
    $self->schema->txn_do(
        sub {
            $self->_persist_run();
            unless ( $self->commit ) {
                $self->log->warn( "Rollback" );
                $self->schema->txn_rollback;
            }            
        }
    );
}

sub _persist_run {
    my $self = shift;

    my $qc_run = $self->_create_qc_run;

    $self->_persist_seq_reads( $qc_run );    
    
    for my $subdir ( $self->analysis_dir->children ) {
        for my $yaml_file ( $subdir->children ) {
            my $analysis = YAML::Any::LoadFile( $yaml_file );
            $self->_create_qc_test_result( $qc_run, $analysis );                      
        }
    }
}

sub _persist_seq_reads {
    my ( $self, $qc_run ) = @_;

    my %seen;

    for my $seq_read_id ( $self->seq_read_ids ) {
        next if $seen{$seq_read_id}++;
        my $seq_read = $self->_find_or_create_seq_read( $seq_read_id );
        $qc_run->create_related( qc_run_seq_reads => { qc_seq_read_id => $seq_read_id } );
    }

    return;
}

sub _create_qc_test_result {
    my ( $self, $qc_run, $analysis ) = @_;
        
    my $synvec = $self->_find_or_create_synvec( $analysis->{target_id} );
    
    my $score = sum( map { $_->{cigar}{score} || 0 } values %{ $analysis->{primers} } );

    $self->log->debug( "Create QCTestResult: "
                           . $synvec->qc_synvec_id . '/' . $analysis->{query_well} );

    my ( $plate_name, $well_name ) = $analysis->{query_well} =~ m/^(.+)([a-zA-Z]\d{2})$/;

    #es cell cant detect if soemthing has passed properly because the primers can be in different files,
    #so you could have an LR in the _A and R2R in the _B, meaning they get processed separately.
    #so we need to double check if we passed or not now we've definitely got all the primers
    if ( $self->profile->is_es_cell ) {
        my %extracted_primers; 

        #the primers are all named like B_R2R so strip the rubbish from the start.

        for my $primer ( keys %{ $analysis->{ primers } } ) {
            my ( $extracted ) = $primer =~ /\w_(\w+)/;

            next unless $extracted; #this shouldn't really ever happen

            $extracted_primers{ $extracted } = $analysis->{ primers }{ $primer };
        }

        #$self->log->debug( "Extracted primers:" . join ",", keys %extracted_primers );

        #now re-check.
        $analysis->{ pass } = $self->profile->is_pass( \%extracted_primers );
    }
    
    my $test_result = $qc_run->create_related(
        test_results => {
            qc_synvec_id => $synvec->qc_synvec_id,
            plate_name   => $plate_name,
            well_name    => $well_name,
            score        => $score,
            pass         => $analysis->{pass} ? 1 : 0
        }
    );

    for my $alignment ( values %{ $analysis->{primers} } ) {
        $self->_create_qc_test_result_alignment( $test_result, $alignment );
    }
}

sub _create_qc_test_result_alignment {
    my ( $self, $test_result, $alignment ) = @_;

    my $qc_seq_read = $self->_find_or_create_seq_read( $alignment->{cigar}{query_id} );

    $self->log->debug( "Create QCTestResultAlignment: "
                           . $test_result->synvec->design_id . "/" . $alignment->{primer} );

    my $alignment_row =
        $test_result->result_source->schema->resultset( 'QCTestResultAlignment' )->create( {
            qc_seq_read_id => $qc_seq_read->qc_seq_read_id,
            primer_name    => $alignment->{primer},
            query_start    => $alignment->{cigar}{query_start},
            query_end      => $alignment->{cigar}{query_end},
            query_strand   => $alignment->{cigar}{query_strand} eq '+' ? 1 : -1,
            target_start   => $alignment->{cigar}{target_start},
            target_end     => $alignment->{cigar}{target_end},
            target_strand  => $alignment->{cigar}{target_strand} eq '+' ? 1 : -1,
            score          => $alignment->{cigar}{score},
            op_str         => $alignment->{cigar}{op_str},
            pass           => $alignment->{pass} ? 1 : 0,
            features       => join( q{,}, @{ $alignment->{features} } ) || q{ },
            cigar          => $alignment->{cigar}{raw}
        } );

    $test_result->create_related( 'test_result_alignment_maps' => {
        qc_test_result_alignment_id => $alignment_row->qc_test_result_alignment_id
    } );    

    for my $region_name ( keys %{ $alignment->{alignment} } ) {
        my $region = $alignment->{alignment}->{$region_name};
        next unless $region->{length} > 0;        
        $self->log->debug( "Create QCTestResultAlignmentRegion: " . $alignment->{primer} . "/" . $region_name );
        $alignment_row->create_related(
            align_regions => {
                name        => $region_name,
                length      => $region->{length} || 0,
                match_count => $region->{match_count} || 0,
                target_str  => $region->{target_str} || ' ', # hack as Oracle seems to be interpreting
                match_str   => $region->{match_str} || ' ',  # an empty string as null :-(
                query_str   => $region->{query_str} || ' ',
                pass        => $region->{pass} ? 1 : 0
            }
        );
    }

    return $alignment_row;
}

sub _find_or_create_seq_read {
    my ( $self, $seq_read_id ) = @_;

    my $seq_read = $self->schema->resultset( 'QCSeqRead' )->find(
        {
            qc_seq_read_id => $seq_read_id
        }
    );

    return $seq_read if $seq_read;
    
    my $bio_seq = $self->seq_read( $seq_read_id )
        or HTGT::QC::Exception->throw( "Sequence read $seq_read_id not found" );

    $self->log->debug( "Create QCSeqRead: " . $seq_read_id );
    
    return $self->schema->resultset( 'QCSeqRead' )->create(
        {
            qc_seq_read_id => $seq_read_id,            
            description    => $bio_seq->desc || '',
            seq            => $bio_seq->seq,
            length         => $bio_seq->length,
        }
    );
}

sub _find_or_create_synvec {
    my ( $self, $target_id ) = @_;

    my ( $design_id, $cassette, $backbone, $flp_cre ) = split /\#/, $target_id, 4;

    HTGT::QC::Exception->throw( "Failed to parse target_id '$target_id'" )
            unless defined $design_id
                and defined $cassette
                    and ( $self->vector_stage eq 'allele' or defined $backbone );
    
    my $apply_flp = defined $flp_cre && $flp_cre =~ /flp/ ? 1 : 0;
    my $apply_cre = defined $flp_cre && $flp_cre =~ /cre/ ? 1 : 0;
    my $apply_dre = defined $flp_cre && $flp_cre =~ /dre/ ? 1 : 0;
    
    my $gbk_data = $self->eng_seqs_dir->file( $target_id . '.gbk' )->slurp;
    my $sha1_sum = sha1_hex( $gbk_data );

    $self->log->debug( "Find or create QCSynvec: " . $sha1_sum );    

    return $self->schema->resultset( 'QCSynvec' )->find_or_create(
        qc_synvec_id => $sha1_sum,
        design_id    => $design_id,
        cassette     => $cassette,
        backbone     => $backbone,
        vector_stage => $self->vector_stage,
        apply_flp    => $apply_flp,
        apply_cre    => $apply_cre,
        apply_dre    => $apply_dre,
        genbank      => $gbk_data
    );
}

sub _create_qc_run {
    my ( $self ) = @_;
    
    my $template_plate = $self->schema->resultset( 'Plate' )->find(
        {
            name => $self->template_plate_name
        }
    ) or HTGT::QC::Exception->throw( 'Template plate ' . $self->template_plate_name . ' not found' );

    $self->log->debug( "Create QCRun: " . $self->qc_run_id );

    return $self->schema->resultset( 'QCRun' )->create(
        {
            qc_run_id          => $self->qc_run_id,
            qc_run_date        => \'current_timestamp',
            sequencing_project => join( q{,}, $self->sequencing_projects ),
            template_plate_id  => $template_plate->plate_id,
            profile            => $self->profile_name,
            software_version   => $self->config->software_version
        }
    );
}

1;

__END__
