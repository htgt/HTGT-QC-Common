package HTGT::QC::Util::DesignLocForPlate;

use strict;
use warnings FATAL => 'all';

use Sub::Exporter -setup => {
    exports => [ 'design_loc_for_plate', 'design_loc_for_epd_plate' ]
};

use HTGT::DBFactory;
use HTGT::QC::Exception;

sub design_loc_for_plate {
    my $plate_name = shift;

    my $htgt = HTGT::DBFactory->connect( 'eucomm_vector' );

    my $plate = $htgt->resultset( 'Plate' )->find(
        { name => $plate_name },
        { prefetch => { 'wells' => 'design_instance' } }
    ) or HTGT::QC::Exception->throw( "Plate $plate_name not found" );

    my %design_loc_for;

    for my $well ( $plate->wells ) {
        my $well_name = uc substr( $well->well_name, -3 );        
        if ( my $di = $well->design_instance ) {            
            $design_loc_for{ $well_name } = $di->design_id;
        }
    }

    return \%design_loc_for;
}

sub design_loc_for_epd_plate {
    my $ep_template_name = shift;
    my $htgt = HTGT::DBFactory->connect( 'eucomm_vector' );

    my $plate = $htgt->resultset( 'Plate' )->find(
        { name => $ep_template_name},
        { prefetch => { 'wells' => 'design_instance' } }
    ) or HTGT::QC::Exception->throw( "Plate $ep_template_name not found" );

    my %design_loc_for;

    #The template here will be BASED on an ep-plate. The kids of the ep are a set of epds.
    #The expected design-loc depends on epd-plate name and well-loc
    foreach my $well ( $plate->wells ) {
        my $ep_well = $well->parent_well;
        if ( my $di = $well->design_instance ) {            
          foreach my $child_well ($ep_well->child_wells){
            # Well name 'EPD0921_1_A05' has to be replaced by 'A05'
            if($child_well->well_name =~ /\S+_\S+_(\S+)/){
                $design_loc_for{ $child_well->plate->name }{ $1 } = $di->design_id;
            }else{
                $design_loc_for{ $child_well->plate->name }{ $child_well->well_name } = $di->design_id;
            }
          }
        }
    }

    return \%design_loc_for;
}

1;

__END__
