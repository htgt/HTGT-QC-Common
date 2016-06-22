package HTGT::QC::Action::Persist::DeleteHTGTDB;

use Moose;
use HTGT::DBFactory;
use namespace::autoclean;

extends 'HTGT::QC::Action';

override command_names => sub {
    'delete-htgt-qc-run'
};

override abstract => sub {
    'delete a QC run from the HTGT database'
};

has qc_run_id => (
    is       => 'ro',
    isa      => 'Str',
    traits   => [ 'Getopt' ],
    cmd_flag => 'run-id',
    required => 1    
);

has commit => (
    is      => 'ro',
    isa     => 'Bool',
    traits  => [ 'Getopt' ],
    default => 0
);

has schema => (
    is      => 'ro',
    isa     => 'HTGTDB',
    traits  => [ 'NoGetopt' ],
    default => sub { HTGT::DBFactory->connect( 'eucomm_vector' ) }
);

sub execute {
    my ( $self, $opt, $args ) = @_;

    $self->schema->txn_do(
        sub {
            my $qc_run = $self->schema->resultset( 'QCRun' )->find( { qc_run_id => $self->qc_run_id } )
                or die "QC run " . $self->qc_run_id . " not found";

            $qc_run->qc_run_seq_reads_rs->delete;            
            
            for my $qc_result ( $qc_run->test_results ) {
                $self->log->info( "Deleting alignment maps for QCResult " . $qc_result->qc_test_result_id );
                my @alignments;
                for my $amap ( $qc_result->test_result_alignment_maps ) {
                    $self->log->info( "Deleting QCTestResultAlignmentMap "
                                          . $amap->qc_test_result_alignment_id );                    
                    push @alignments, $amap->alignment;
                    $amap->delete;
                }
                for my $alignment ( @alignments ) {
                    next if $alignment->test_results > 0;
                    $self->log->info( "Deleting alignment " . $alignment->qc_test_result_alignment_id );
                    $alignment->align_regions_rs->delete;
                    $alignment->delete;
                }
                $self->log->info( "Deleting QCResult " . $qc_result->qc_test_result_id );
                $qc_result->delete;
            }

            $self->log->info( "Deleting QCRun " . $qc_run->qc_run_id );
            $qc_run->delete;

            unless ( $self->commit ) {
                $self->log->info( "Rollback" );
                $self->schema->txn_rollback;
            }
        }
    );
}

__PACKAGE__->meta->make_immutable;

1;

__END__
