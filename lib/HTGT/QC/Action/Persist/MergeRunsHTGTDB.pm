package HTGT::QC::Action::Persist::MergeRunsHTGTDB;

use Moose;
use namespace::autoclean;

use HTGT::QC::Util::MergeQCRuns 'merge_qc_runs';
use HTGT::DBFactory;
use Data::Dump 'pp';

extends 'HTGT::QC::Action';

override command_names => sub {
    'merge-htgt-qc-runs'
};

override abstract => sub {
    'merge one or more QC runs in the HTGT database'
};

has plate_name_map => (
    is       => 'ro',
    isa      => 'HashRef',
    traits   => [ 'Getopt' ],
    required => 1,
    cmd_flag => 'map'
);

has single_run => (
    is       => 'ro',
    isa      => 'Bool',
    traits   => [ 'Getopt' ],
    cmd_flag => 'single-run',
    default  => 0
);

has commit => (
    is      => 'ro',
    isa     => 'Bool',
    traits  => [ 'Getopt' ],
    default => 0
);

has schema => (
    is         => 'ro',
    isa        => 'HTGTDB',
    traits     => [ 'NoGetopt' ],
    lazy_build => 1
);

sub _build_schema {
    HTGT::DBFactory->connect( 'eucomm_vector' );
}

sub execute {
    my ( $self, $opt, $args ) = @_;

    if ( $self->single_run ) {
        die "Exactly one run must be specified for the --single-run option\n"
            unless @{$args} == 1;
    }
    else {
        die "At least two QC run ids must be given\n"
            unless @{$args} >= 2;
    }
    
    $self->schema->txn_do(
        sub {
            my $merged_run = merge_qc_runs( $self->schema, $self->config, $self->plate_name_map, $args );
            print "Created QC run " . $merged_run->qc_run_id . "\n";
            unless ( $self->commit ) {
                warn "Rollback\n";
                $self->schema->txn_rollback;
            }
        }
    );
}

__PACKAGE__->meta->make_immutable;

1;

__END__
