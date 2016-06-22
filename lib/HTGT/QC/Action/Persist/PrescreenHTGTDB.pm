package HTGT::QC::Action::Persist::PrescreenHTGTDB;

use Moose;
use HTGT::DBFactory;
use List::Util qw( first );
use List::MoreUtils qw ( uniq );
use YAML::Any;
use namespace::autoclean;
use HTGT::QC::Util::ListTraceProjects;

extends qw( HTGT::QC::Action::Persist );

override command_names => sub {
    'persist-prescreen-htgtdb'
};

override abstract => sub {
    'persist prescreen test results to HTGT database'
};

has schema => (
    is      => 'ro',
    isa     => 'HTGTDB',
    default => sub { HTGT::DBFactory->connect( 'eucomm_vector' ) }
);

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

    my %wells = $self->get_well_data();

    #now persist all the information we just collected
    $self->log->debug( "Persisting prescreen data for " . $self->qc_run_id );

    while ( my ( $well_name, $genes ) = each %wells ) {
        #we DO allow an entry with no genes
        #we only want unique genes. separate them with a ;
        my $genes = join ";", uniq( @{ $genes } );

        if( length( $genes ) >= 600 ) {
            $self->log->warn( "List of genes will be truncated as it exceeds 600 characters." );
        }

        $self->log->debug( "Adding marker symbols for $well_name: $genes" );

        my $well = $self->get_well_object( $well_name );

        #add all the marker symbols
        $well->update_or_create_related(
            well_data => {
                data_type  => 'prescreen_gene',
                data_value => substr( $genes, 0, 600 ), #dont exceed field length
                edit_date  => \'current_timestamp',
            }
        );

        #add the run id so we can provide a link to this data on disc
        $well->update_or_create_related(
            well_data => {
                data_type  => 'prescreen_run_id',
                data_value => $self->qc_run_id,
                edit_date  => \'current_timestamp',
            }
        );
    }
}

sub get_well_object {
    my ( $self, $well_name ) = @_;

    my $well = $self->schema->resultset( 'Well' )->find( 
        { well_name => $well_name } 
    );

    #if we didnt get a well object we need to try with different leading zeroes
    unless( $well ) {
        $self->log->debug( "Couldn't find '$well_name', trying without leading zeroes." );
        #split the well_name into parts: HEPD0855_2_A03 -> HEPD0855 and _2_A03
        my ( $plate, $remaining ) = $well_name =~ /^(\D+\d+)(_.*)/;

        #get all the possible combinations (e.g. HEPD855, HEPD0855, HEPD00855, HEPD000855)
        my @names = HTGT::QC::Util::ListTraceProjects->new()->expand_leading_zeroes( $plate );

        #see if any of them got us a well object
        for my $plate_name ( @names ) {
            $well = $self->schema->resultset( 'Well' )->find( 
                { well_name => $plate_name . $remaining } 
            );

            last if $well;
        }

        die "Couldn't find well '$well_name' in the database, aborting."
            unless $well;
    }

    return $well;
}

sub get_well_data {
    my ( $self ) = @_;
    #generate a hash of wells and all their corresponding marker symbols from the yaml files

    $self->log->debug( "Extracting well data from prescreen files." );

    #for the analysis_dir we expect qc_run_folder/prescreen
    my %wells;
    for my $file ( $self->analysis_dir->children ) {
        my $yaml_data = YAML::Any::LoadFile( $file );
        #query_id is something like HEPD0855_2_A_1a03.p1kLR
        while ( my ( $query_id, $cigars ) = each %{ $yaml_data } ) {
            #make sure the highest score is first
            my @sorted = sort { $b->{score} <=> $a->{score} } @{ $cigars };
            if ( @{ $cigars } > 1 ) {
                #if the first entry is iftim2 and we have more than one alignment, remove the Ifitm2 one.
                if ( first { $_ eq "Ifitm2" } @{ $sorted[0]->{genes} } ) {
                    $self->log->debug( "Ignoring Ifitm2 in $query_id" );
                    shift @sorted;
                }
            }

            #take the cigar with the best score
            my $cigar = shift @sorted;

            #the epd plates get split into _A, _B, _Z etc., but they are the same plate,
            #so we need to extract the unsplit name,
            #i.e. reduce HEPD0855_2_A_1A03 to HEPD0855_2_A03
            #or HEPD0855_2_A_1_1A03
            my ( $plate_name, $plate_well ) = $cigar->{ query_well } =~ /(\w+_\d{1,2})_\w_.*\w(\w{3})/;

            my $adjusted_well_name = $plate_name . "_" . $plate_well;

            #ignore None found as its obviously not a gene
            my @valid_genes = grep { $_ !~ /None found/ } @{ $cigar->{ genes } };

            #use the adjusted well name as a key as it corresponds directly to a db entry.
            #we make this a list as the same well can have different genes 
            push @{ $wells{ $adjusted_well_name } }, @valid_genes;
        }
    }

    return %wells;
}

1;

__END__
