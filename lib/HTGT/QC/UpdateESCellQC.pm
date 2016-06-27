package HTGT::QC::UpdateESCellQC;

use strict;
use warnings FATAL => 'all';

use Log::Log4perl qw( :easy );
use HTGT::Utils::QCTestResults qw( fetch_test_results_for_run );
use Sub::Exporter -setup => {
    exports => [ qw( update_ES_plate ) ]
};


sub update_ES_plate{
    my ( $schema, $orig_plate_name, $plate_name, $qc_run, $user_id ) = @_;

    my %template_wells = map { uc( substr( $_->well_name, -3) ) => $_ }
        grep { defined $_->design_instance_id } $qc_run->template_plate->wells;

    my $results = fetch_test_results_for_run( $schema, $qc_run->qc_run_id );

    my @updated;

    my %results_by_well;
    for my $r( @{$results} ) {
        next unless $r->{plate_name} eq $orig_plate_name;
        next unless $r->{design_id}; 
        next unless $r->{expected_design_id} eq $r->{design_id}; 

        push @{ $results_by_well{ uc ( substr( $r->{well_name}, -3 ) ) } }, $r;
    }

    DEBUG( "Updating plate $plate_name" );

    my $plate = $schema->resultset( 'Plate' )->find( { name => $plate_name } )
        or die "Failed to retrieve plate $plate_name";

    #add a new entry to plate_data so runs on a plate can be easily identified.
    if( keys %results_by_well ) { #make sure we are actually going to update.
        $plate->update_or_create_related(
            plate_data => {
                data_type  => 'linked_qc_run',
                data_value => $qc_run->qc_run_id,
                edit_date  => \'current_timestamp',
                edit_user  => $user_id
            }
        );
    }

    for my $well_name( keys %results_by_well ){
        my $qc_test_run_id_for_well = join( '/', $qc_run->qc_run_id, $plate_name, $well_name );
        my $full_well_name = $well_name =~ /^\D\d\d$/ ? $plate_name . '_' . $well_name : $well_name;
        my $well = _update_well_on_plate( $schema, $plate, $full_well_name, $results_by_well{$well_name}, $qc_test_run_id_for_well, $user_id );
    }

    return $plate;
}

sub _update_well_on_plate{
    my ( $schema, $plate, $well_name, $results, $qc_test_result_id, $user_id ) = @_;

    DEBUG( 'Updating well ' . $well_name . ' on plate ' . $plate->name );

    my $best_result = $results->[0];
    my $design_id = $best_result->{design_id};

    my $well = $schema->resultset( 'Well' )->find( { well_name => $well_name } );

    if ( $best_result->{num_valid_primers} > 0 ){
        $well->update_or_create_related(
            well_data => {
                data_type => 'valid_primers',
                data_value => join( q{,}, @{ $best_result->{valid_primers} } ),
                edit_date => \'current_timestamp',
                edit_user => $user_id
            }
        );
    }

    my %well_data = (
        pass_level => ( $best_result->{pass} ? 'pass' : 'fail' ),
        new_qc_test_result_id => $qc_test_result_id,
        obs_design_id => $design_id
    );

    if ( @{$results} > 1 ){
        $well_data{mixed_reads} = 'yes';
    }

    for my $data_type( keys %well_data ){
        $well->update_or_create_related(
            well_data => {
                data_type => $data_type,
                data_value => $well_data{$data_type},
                edit_date => \'current_timestamp',
                edit_user => $user_id
            }
        );
    }

    return $well;
}

1;

__END__
