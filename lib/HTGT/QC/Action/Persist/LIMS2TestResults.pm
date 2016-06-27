package HTGT::QC::Action::Persist::LIMS2TestResults;

use Moose;
use List::Util qw( sum );
use YAML::Any;
use Try::Tiny;
use namespace::autoclean;

extends qw( HTGT::QC::Action::Persist );
with qw( HTGT::QC::Util::LIMS2Client );

override command_names => sub {
    'persist-lims2-test-results'
};

override abstract => sub {
    'persist qc test results for a qc run to LIMS2 database'
};

sub execute {
    my ( $self, $opts, $args ) = @_;

    $self->_process_qc_test_results;

    $self->log->debug( "Added test results to QCRun: " . $self->qc_run_id
                        . ' setting upload_complete to true');
    try{
        $self->lims2_client->PUT( 'qc_run', { id => $self->qc_run_id }, { upload_complete => 1 } );
    }
    catch {
        HTGT::QC::Exception->throw( 'Error persisting qc_run data to LIMS2 for qc_run '
            . $self->qc_run_id . ' : ' . $_ );
    };
}

sub _process_qc_test_results {
    my $self = shift;
    my @test_result_params;

    for my $subdir ( $self->analysis_dir->children ) {
        for my $yaml_file ( $subdir->children ) {
            my $analysis = YAML::Any::LoadFile( $yaml_file );

            #es cell cant detect if soemthing has passed properly because the primers can be in different files,
            #so you could have an LR in the _A and R2R in the _B, meaning they get processed separately.
            #so we need to double check if we passed or not now we've definitely got all the primers
            if ( $self->profile->is_es_cell ) {
                #$self->log->debug( "Extracted primers:" . join ",", keys %extracted_primers );

                #now do the re-check
                $analysis->{ pass } = $self->profile->is_pass( $analysis->{ primers } );
            }

            $self->_create_qc_test_result( $analysis );
        }
    }
}

sub _create_qc_test_result {
    my ( $self, $analysis ) = @_;

    $self->log->debug( "Create QCTestResult: " . $analysis->{query_well} );

    my $score = sum( map { $_->{cigar}{score} || 0 } values %{ $analysis->{primers} } );

    my $eng_seq_id = $analysis->{target_id};

    try{
        $self->lims2_client->POST( 'qc_test_result',
            {
                qc_run_id     => $self->qc_run_id,
                qc_eng_seq_id => $eng_seq_id,
                pass          => $analysis->{pass} ? 1 : 0,
                score         => $score,
                alignments    => $self->_process_qc_test_result_alignments( $analysis->{primers}, $eng_seq_id ),
            }
        );
    }
    catch {
        HTGT::QC::Exception->throw( 'Error persisting test result data '
            . $analysis->{query_well} . ' to LIMS2 for qc_run '
            . $self->qc_run_id . ' : ' . $_ );
    };
}

sub _process_qc_test_result_alignments {
    my ( $self, $alignments, $eng_seq_id ) = @_;

    my @alignments;

    for my $alignment ( values %{ $alignments } ) {
        $self->log->debug( "Process QCTestResultAlignment: " . $alignment->{primer} );

        push @alignments, {
            qc_seq_read_id    => $alignment->{cigar}{query_id},
            qc_eng_seq_id     => $eng_seq_id,
            primer_name       => $alignment->{primer},
            query_start       => $alignment->{cigar}{query_start},
            query_end         => $alignment->{cigar}{query_end},
            query_strand      => $alignment->{cigar}{query_strand} eq '+' ? 1 : -1,
            target_start      => $alignment->{cigar}{target_start},
            target_end        => $alignment->{cigar}{target_end},
            target_strand     => $alignment->{cigar}{target_strand} eq '+' ? 1 : -1,
            score             => $alignment->{cigar}{score},
            pass              => $alignment->{pass} ? 1 : 0,
            features          => join( q{,}, @{ $alignment->{features} } ) || q{ },
            cigar             => $alignment->{cigar}{raw},
            op_str            => $alignment->{cigar}{op_str},
            alignment_regions => $self->_process_alignment_regions( $alignment->{alignment} ),
        };
    }

    return \@alignments;
}

sub _process_alignment_regions {
    my ( $self, $alignment_regions ) = @_;

    my @alignment_regions;

    for my $region_name ( keys %{ $alignment_regions } ) {
        my $region = $alignment_regions->{$region_name};
        next unless $region->{length} > 0;
        $self->log->debug( "Create QCTestResultAlignmentRegion: " . $region_name );

        push @alignment_regions,
            {
                name        => $region_name,
                length      => $region->{length}      || 0,
                match_count => $region->{match_count} || 0,
                query_str   => $region->{query_str}   || '',
                target_str  => $region->{target_str}  || '',
                match_str   => $region->{match_str}   || '',
                pass        => $region->{pass} ? 1 : 0,
            };
    }

    return \@alignment_regions;
}


1;

__END__
