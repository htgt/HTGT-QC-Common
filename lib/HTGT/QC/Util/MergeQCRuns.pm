package HTGT::QC::Util::MergeQCRuns;

use strict;
use warnings FATAL => 'all';

use Sub::Exporter -setup => {
    exports => [ qw( merge_qc_runs ) ]
};

use HTGT::QC::Exception;
use List::Util qw( sum );
use List::MoreUtils qw( uniq );
use Data::UUID;
use Parse::BooleanLogic;
use Log::Log4perl qw( :easy );
use JSON;

sub merge_qc_runs {
    my ( $schema, $config, $plate_name_map, $qc_run_ids ) = @_;

    my $qc_runs             = fetch_qc_runs( $schema, $qc_run_ids );
    my $template_plate      = get_template_plate( $qc_runs );
    my $profile             = get_profile( $config, $qc_runs );
    
    my $pass_condition      = $profile->pass_condition
        or HTGT::QC::Exception->throw( 'No pass_condition configured for profile ' . $profile->profile_name );

    my @sequencing_projects = uniq map { $_->sequencing_project } @{ $qc_runs };

    my @all_results         = map { $_->test_results } @{ $qc_runs };
    my @plate_names         = uniq map { $_->plate_name } @all_results;    
    
    for my $plate_name ( @plate_names ) {        
        unless ( exists $plate_name_map->{ $plate_name } ) {            
            HTGT::QC::Exception->throw( "No plate name map defined for '$plate_name'" );
        }
    }
    
    my $merged_run = $schema->resultset( 'QCRun' )->create(
        {
            qc_run_id          => Data::UUID->new->create_str,
            qc_run_date        => \'current_timestamp',
            sequencing_project => join( q{,}, sort @sequencing_projects ),
            template_plate_id  => $template_plate->plate_id,
            profile            => $profile->profile_name,
            software_version   => $config->software_version,
            plate_map          => encode_json($plate_name_map) #to identify a run as merged
        }
    );
    DEBUG( "Created merged run with id: " . $merged_run->qc_run_id );

    my %input_plates_for;
    while ( my ( $input_plate, $dest_plate ) = each %{$plate_name_map} ) {
        $input_plates_for{$dest_plate}{$input_plate}++;
    }    
    
    for my $new_plate_name ( sort keys %input_plates_for ) {
        my @this_plate_results = grep {
            $input_plates_for{$new_plate_name}{ $_->plate_name }
        } @all_results;
        _merge_plate_results( $pass_condition, $merged_run, $new_plate_name, \@this_plate_results );
    }

    return $merged_run;
}

sub _merge_plate_results {
    my ( $pass_condition, $qc_run, $plate_name, $results ) = @_;

    DEBUG( "Merging results for plate: " . $plate_name );
    
    for my $well_name ( uniq map { $_->well_name } @{ $results } ) {
        my @this_well_results = grep { $_->well_name eq $well_name } @{ $results };
        _merge_well_results( $pass_condition, $qc_run, $plate_name, $well_name, \@this_well_results );
    }
}

sub _merge_well_results {
    my ( $pass_condition, $qc_run, $plate_name, $well_name, $results ) = @_;

    DEBUG( "Merging results for well: " . $well_name );
    
    for my $synvec_id ( uniq map { $_->qc_synvec_id } @{ $results } ) {
        DEBUG( "Merging results for synvec: " . $synvec_id );        
        my @this_synvec_results = grep { $_->qc_synvec_id eq $synvec_id } @{ $results };
        my @alignments = map { $_->alignments } @{ $results };
        my %best_alignments;
        for my $primer_name ( uniq map { $_->primer_name } @alignments ) {
            DEBUG( "Selecting best alignment for primer $primer_name" );
            my @this_primer_alignments = grep { $_->primer_name eq $primer_name } @alignments;
            $best_alignments{ $primer_name } = _best_alignment( \@this_primer_alignments );
        }
        my $test_result = $qc_run->create_related(
            test_results => {
                qc_synvec_id => $synvec_id,
                plate_name   => $plate_name,
                well_name    => $well_name,
                score        => sum( map { $_->score } values %best_alignments ),
                pass         => _check_pass_condition( $pass_condition, \%best_alignments )
            }
        );
        DEBUG( "Created QCTestResult with id: " . $test_result->qc_test_result_id );
        for my $alignment ( values %best_alignments ) {
            $test_result->create_related(
                test_result_alignment_maps => {
                    qc_test_result_alignment_id => $alignment->qc_test_result_alignment_id
                }
            );
        }
    }
}

sub _check_pass_condition {
    my ( $pass_condition, $primer_results ) = @_;    
    
    my $callback = sub {
        my $primer = $_[0]->{operand};
        exists $primer_results->{$primer} && $primer_results->{$primer}->pass;
    };

    my $parser = Parse::BooleanLogic->new;
    $parser->solve( $parser->as_array( $pass_condition ), $callback ) || 0;
}

sub _best_alignment {
    my ( $alignments ) = @_;

    my @ranked = reverse sort { $a->score <=> $b->score } @{$alignments};

    if ( my @passes = grep { $_->pass } @ranked ) {
        return shift @passes;
    }

    return shift @ranked;
}

sub fetch_qc_runs {
    my ( $schema, $qc_run_ids ) = @_;

    my @qc_runs = $schema->resultset( 'QCRun' )->search_rs(
        {
            'me.qc_run_id' => $qc_run_ids
        },
        {
            prefetch => 'test_results'
        }
    )->all;

    my %found_run = map { $_->qc_run_id => 1 } @qc_runs;
    
    DEBUG( "fetch_qc_runs, found: " . join( q{, }, sort keys %found_run ) );

    if ( keys %found_run != @{ $qc_run_ids } ) {
        my @missing = grep { ! $found_run{$_} } @{ $qc_run_ids };
        HTGT::QC::Exception->throw( "Failed to retrieve QC run(s): " . join( q{,}, @missing ) );
    }

    return \@qc_runs;
}

sub get_profile {
    my ( $config, $qc_runs ) = @_;

    my %profiles = map { $_->profile => 1 } @{ $qc_runs };

    DEBUG( "get_profile_name, found: " . join( q{, }, sort keys %profiles ) );
    
    if ( keys %profiles > 1 ) {
        HTGT::QC::Exception->throw( "QC runs with different profiles cannot be merged" );
    }

    my $profile_name = ( keys %profiles )[0];

    return $config->profile( $profile_name );
}

sub get_template_plate {
    my $qc_runs = shift;

    my %plates = map { $_->name => $_ } map { $_->template_plate } @{ $qc_runs };

    DEBUG( "get_template_plates, found: " . join( q{, }, sort keys %plates ) );

    if ( keys %plates > 1 ) {
        HTGT::QC::Exception->throw( "QC runs with different template plates cannot be merged" );
    }

    return ( values %plates )[0];
}

1;

__END__
