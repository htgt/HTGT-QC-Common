package HTGT::QC::Util::GeneratePrimersAttempts;
## no critic(RequireUseStrict,RequireUseWarnings)
{
    $HTGT::QC::Util::GeneratePrimersAttempts::VERSION = '0.050';
}
## use critic


=head1 NAME

HTGT::QC::Util::GeneratePrimersAttempts

=head1 DESCRIPTION

Wrapper around HTGT::QC::Util::GeneratePrimers
If initial generation of primers fails this module will automatically try again
to generate the primers by expanding the search region for the primers.

=cut

use Moose;
use MooseX::Types::Path::Class::MoreCoercions qw/AbsDir AbsFile/;
use HTGT::QC::Util::GeneratePrimers;
use WebAppCommon::Util::EnsEMBL;
use Bio::Seq;
use Path::Class;
use Try::Tiny;
use namespace::autoclean;

with qw( MooseX::Log::Log4perl );

has base_dir => (
    is       => 'ro',
    isa      => AbsDir,
    required => 1,
    coerce   => 1,
);

has species => (
    is       => 'ro',
    isa      => 'Str',
    required => 1,
);

has strand => (
    is       => 'ro',
    isa      => 'Int',
    required => 1,
);

has chromosome => (
    is       => 'ro',
    isa      => 'Str',
    required => 1,
);

# genomic coordinates for target
has [ 'target_start', 'target_end' ] => (
    is       => 'ro',
    isa      => 'Int',
    required => 1,
);

has ensembl_util => (
    is         => 'ro',
    isa        => 'WebAppCommon::Util::EnsEMBL',
    lazy_build => 1,
);

sub _build_ensembl_util {
    my $self = shift;

    my $ensembl_util = WebAppCommon::Util::EnsEMBL->new( species => $self->species );

    # this flag should stop the database connection being lost on long jobs
    $ensembl_util->registry->set_reconnect_when_lost;

    return $ensembl_util;
}

#
# Primer Regions
#

# if we have a forward primer, only look for reverse primer
has forward_primer => (
    is        => 'ro',
    isa       => 'HashRef',
    predicate => 'have_forward_primer',
);

has [
    'five_prime_region_size',   'three_prime_region_size',
    'five_prime_region_offset', 'three_prime_region_offset'
    ] => (
    is       => 'rw',
    isa      => 'Int',
    required => 1,
);

# default of masking all sequence ensembl considers to be a repeat region
# means passing in undef as a mask method, otherwise pass in array ref of repeat classes
has repeat_mask_class => (
    is      => 'ro',
    isa     => 'ArrayRef',
    traits  => [ 'Array' ],
    default => sub{ [] },
    handles => {
        no_repeat_mask_classes => 'is_empty'
    },
);

# Set this flag to true to prevent all repeat masking regardless of repeat_mask_class contents
has no_repeat_masking => (
    is      => 'ro',
    isa     => 'Bool',
    default => 0,
);

has [ 'max_five_prime_region_size', 'max_three_prime_region_size' ] => (
    is  => 'ro',
    isa => 'Int',
);

=head2 sequence_regions

optional array of genomic coordinates for regions of interest.

sequence_included_region:
Tells Primer3 which regions to pick primers in.

sequence_excluded_region:
Tells Primer3 which regions to avoid picking primers in.

Each element of list is a hashref in the form:
{ start => 111, end => 222 }

=cut
has [ 'excluded_regions', 'included_regions' ] => (
    is      => 'ro',
    isa     => 'ArrayRef',
    default => sub{ [] },
);

#
# Primer3 Parameters
#

has primer3_task => (
    is      => 'ro',
    isa     => 'Str',
    default => 'pick_pcr_primers',
);

has primer3_config_file => (
    is       => 'ro',
    isa      => AbsFile,
    required => 1,
);

# any additional optional parameters not specified in primer3 config file
# passed directly to Primer3 Util module
has additional_primer3_params => (
    is      => 'ro',
    isa     => 'HashRef',
    default => sub{ {} },
);

# Set custom primer product size ranges, normally we can work it out.
# Should be left blank unless you have strict requirements for the
# product size, may not work with retry attempts
has primer_product_size_range => (
    is  => 'rw',
    isa => 'Str',
);

# primer product size you want to avoid
has product_size_avoid => (
    is  => 'ro',
    isa => 'Int',
);

# offset around product_size_avoid
# e.g. if we specify product_size_avoid = 100 then we avoid
#      product sizes from 70 - 130 by default
has product_size_avoid_offset => (
    is      => 'ro',
    isa     => 'Int',
    default => 30,
);

has product_size_array => (
    is      => 'rw',
    isa     => 'ArrayRef',
    default => sub{ [] },
);

#
# Retry Primer Generation
#

has retry_attempts => (
    is      => 'ro',
    isa     => 'Num',
    default => 4,
);

has current_attempt => (
    is       => 'rw',
    isa      => 'Num',
    default  => 1,
    init_arg => undef,
);

has primer_search_region_expand => (
    is      => 'ro',
    isa     => 'Num',
    default => 500,
);

has check_genomic_specificity => (
    is      => 'ro',
    isa     => 'Bool',
    default => 1,
);

# By default the maximum product length is:
# length of target + five prime region + three prime region
# Use this attribute if you want the max product to be <n> bases shorter than this
has exclude_from_product_length => (
    is      => 'ro',
    isa     => 'Num',
    required => 0,
);

=head2 find_primers

Attempt to generate primers for target, if this fails initially try again
with a increased search area for the primers.

=cut
sub find_primers {
    my ( $self ) = @_;
    $self->log->info( 'ATTEMPT ' . $self->current_attempt . ' at primer generation' );

    if ( $self->have_forward_primer ) {
        $self->additional_primer3_params->{sequence_primer} = $self->forward_primer->{oligo_seq};
    }

    my ( $primers, $seq );
    ( $primers, $seq ) = $self->generate_primer_attempt;
    while ( !$primers && $self->current_attempt < $self->retry_attempts ) {
        last unless $self->setup_new_attempt;
        $self->log->info( '--------' );
        $self->log->info( 'ATTEMPT ' . $self->current_attempt . ' at primer generation' );
        ( $primers, $seq ) = $self->generate_primer_attempt;
    }
    return ( $primers, $seq );
}

=head2 generate_primer_attempt

Run the HTGT::QC::Util::GeneratePrimers modules.
Grab target sequence slice from EnsEMBL.

=cut
sub generate_primer_attempt {
    my ( $self ) = @_;

    my ( $start, $end );
    if ( $self->strand == 1 ) {
        $start = $self->target_start - $self->five_prime_region_size;
        $end   = $self->target_end + $self->three_prime_region_size;
    }
    else {
        $start = $self->target_start - $self->three_prime_region_size;
        $end   = $self->target_end + $self->five_prime_region_size;
    }
    my $seq_slice = $self->build_region_slice( $start, $end );
    my $bio_seq = Bio::Seq->new( -display_id => 'primer_search_region', -seq => $seq_slice->seq );

    my $work_dir = $self->base_dir->subdir( $self->current_attempt );
    $work_dir->mkpath;
    $self->generate_primer_product_size_range( $start, $end );

    my %params = (
        dir                       => $work_dir,
        bio_seq                   => $bio_seq,
        region_start              => $start,
        region_end                => $end,
        species                   => $self->species,
        strand                    => $self->strand,
        primer3_config_file       => $self->primer3_config_file,
        primer3_target_string     => $self->generate_target_string,
        primer_product_size_range => join( ' ', @{ $self->product_size_array } ),
        check_genomic_specificity => $self->check_genomic_specificity,
        primer3_task              => $self->primer3_task,
    );

    if ( @{ $self->excluded_regions } ) {
        $self->additional_primer3_params->{sequence_excluded_region}
            = $self->generate_sequence_region( $self->excluded_regions, $bio_seq );
    }

    if ( @{ $self->included_regions } ) {
        $self->additional_primer3_params->{sequence_included_region}
            = $self->generate_sequence_region( $self->included_regions, $bio_seq );
    }
    $params{additional_primer3_params} = $self->additional_primer3_params,

    my $util = HTGT::QC::Util::GeneratePrimers->new( %params );

    my $primer_data;
    try {
        $primer_data = $util->generate_primers;
    }
    catch {
        $self->log->error("Problem running GeneratePrimers: $_");
    };

    return ( $primer_data, $bio_seq );
}

=head2 setup_new_attempt

Expand primer search region after failing to find primers.
If we have a forward primer ( so are only looking for a reverse primer )
we do not expand the five prime region.

Return true if we are okay to setup new attempt, otherwise false.

=cut
sub setup_new_attempt {
    my ( $self ) = @_;

    $self->current_attempt( $self->current_attempt + 1 );
    $self->log->info( 'Last attempt failed, expanding primer search region' );

    my $new_five_prime_region_size;
    if ( $self->have_forward_primer ) {
        $new_five_prime_region_size = $self->five_prime_region_size;
    }
    else {
        $new_five_prime_region_size = $self->five_prime_region_size + $self->primer_search_region_expand;
    }

    my $new_three_prime_region_size = $self->three_prime_region_size + $self->primer_search_region_expand;

    if (   $self->max_five_prime_region_size
        && $new_five_prime_region_size > $self->max_five_prime_region_size )
    {
        $self->log->warn( 'Can not expand five prime any more, hitting used specified limit: '
                . $self->max_five_prime_region_size );
        return;
    }
    elsif ( $self->max_three_prime_region_size
        &&  $new_three_prime_region_size > $self->max_three_prime_region_size )
    {
        $self->log->warn( 'Can not expand three prime any more, hitting used specified limit: '
                . $self->max_three_prime_region_size );
        return;
    }

    $self->five_prime_region_size( $new_five_prime_region_size );
    $self->three_prime_region_size( $new_three_prime_region_size );

    return 1;
}

=head2 generate_target_string

Generate string which tells Primer3 what region the primers must flank.
It is in the form: <start>,<length>
<start> is the index of the first base of the target.
<length> is the the length of the target.

This is the SEQUENCE_TARGET parameter sent into Primer3.

=cut
sub generate_target_string {
    my ( $self ) = @_;

    my $target_start = $self->five_prime_region_size - $self->five_prime_region_offset;
    my $target_length = ( $self->target_end - $self->target_start )
        + ( $self->five_prime_region_offset + $self->three_prime_region_offset );

    my $target_string = "$target_start,$target_length";
    $self->log->debug( "Target string: $target_string" );

    return $target_string;
}

=head2 generate_primer_product_size_range

Generate string which tells Primer3 what how big the product from the primers should be.
It is in the form: <x>-<y>
<x> is the minimum size
<y> is the maximum size

You can specify a list of ranges ( e.g. 100-200 400-500 ). If this is done Primer3 tries
to make products in the first size range, only expanding the the other ranges if it can't
find anything.
We use this property when expanding the search region, favoring products that would be
produced by primers found in the expanded region.

If we have a forward primer specified then the product is always anchored to that primer
so the calculations for the size range is different.

If we have user specified value ( primer_product_size_range attribute ) always use this.

This is the PRIMER_PRODUCT_SIZE_RANGE parameter sent into Primer3.

=cut
sub generate_primer_product_size_range {
    my ( $self, $start, $end ) = @_;

    # user has set custom primer product size range, always use this
    if ( $self->primer_product_size_range ) {
        $self->product_size_array( [ $self->primer_product_size_range ] );
        return;
    }

    my ( $min_size, $max_size );
    if ( $self->have_forward_primer ) {
        my $forward_primer_start = $self->forward_primer->{oligo_start};
        die ('No start value for forward primer') unless $forward_primer_start;

        $max_size = $end - $forward_primer_start;
        if ( $self->current_attempt == 1 ) {
            $min_size = ( $self->target_end - $forward_primer_start )
                + ( $self->five_prime_region_offset + $self->three_prime_region_offset );
        }
        else {
            my $last_size_range = $self->product_size_array->[0];
            $min_size = ( split( /-/, $last_size_range ) )[1];
        }
    }
    else {
        $max_size = $end - $start;
        if ( $self->exclude_from_product_length ){
            $max_size = $max_size - $self->exclude_from_product_length;
        }
        if ( $self->current_attempt == 1 ) {
            $min_size = ( $self->target_end - $self->target_start )
                + ( $self->five_prime_region_offset + $self->three_prime_region_offset );
        }
        else {
            my $last_size_range = $self->product_size_array->[0];
            $min_size = ( split( /-/, $last_size_range ) )[1];
        }
    }
    my $new_size_range = $min_size . '-' . $max_size;

    unshift @{ $self->product_size_array }, $new_size_range;
    $self->log->info( 'Primer product size ranges: ' . join( ' ', @{ $self->product_size_array } ) );

    $self->process_avoid_product_size if $self->product_size_avoid;

    return;
}

=head2 build_region_slice

Build a Bio::EnsEMBL::Slice for a given target regions

=cut
sub build_region_slice {
    my ( $self, $start, $end ) = @_;

    my $slice;
    if($self->no_repeat_masking){
        $slice = $self->ensembl_util->get_slice(
            $start, $end, $self->chromosome,
        );
    }
    else{
        $slice = $self->ensembl_util->get_repeat_masked_slice(
            $start, $end, $self->chromosome,
            $self->no_repeat_mask_classes ? undef : $self->repeat_mask_class
        );
    }

    # primer3 expects sequence in a 5' to 3' direction, so reverse compliment if
    # target is on the -ve strand
    return $self->strand == 1 ? $slice : $slice->invert;
}

=head2 process_avoid_product_size

If user has set a certain size of product to avoid recalculate
the product size range values to avoid this size.

=cut
sub process_avoid_product_size {
    my ( $self ) = @_;

    my $avoid_min = $self->product_size_avoid - $self->product_size_avoid_offset;
    my $avoid_max = $self->product_size_avoid + $self->product_size_avoid_offset;
    my @new_product_size_array;

    for my $range ( @{ $self->product_size_array } ) {
        my ( $min, $max ) = split( '-', $range );

        # avoid range wholy encompasses range
        if ( $avoid_min <= $min && $avoid_max >= $max ) {
            next;
        }
        # range does not overlap avoid min / max
        elsif ( $min >= $avoid_max || $avoid_min >= $max  ) {
            push @new_product_size_array, $min . '-' . $max;
            next;
        }

        if ( $avoid_min > $min && $avoid_min < $max ) {
            push @new_product_size_array, $min . '-' . $avoid_min;
        }

        if ( $avoid_max > $min && $avoid_max < $max ) {
            push @new_product_size_array, $avoid_max . '-' . $max;
        }

    }

    $self->product_size_array( \@new_product_size_array );
    return;
}

=head2 generate_sequence_region

Generate a list of regions to pass to Primer3:
It is in the form of a space seperated list:
<start>,<length> <start>,<length> ...

Must work out coordiantes relative to the sequence we send to Primer3.

Used for following Primer parameters:
SEQUENCE_EXCLUDED_REGION: area to avoid searching for primers
SEQUENCE_INCLUDED_REGION: area to search for primers

=cut
sub generate_sequence_region {
    my ( $self, $regions, $bio_seq ) = @_;
    my @region_list;

    for my $region ( @{ $regions } ) {
        my $length = ( $region->{end} - $region->{start} ) + 1;
        # work out relative start position of region within sequence sent to Primer3
        my $start = $self->five_prime_region_size + ( $region->{start} - $self->target_start );

        # check if region is outside of the sequence we are sending Primer3
        if ( ( $start + $length ) > $bio_seq->length ) {
            if ( $start > $bio_seq->length ) {
                $self->log->warn( 'Specified region is completely outside sequence' );
            }
            # This means the excluded region partially overlaps the sequence
            else {
                push @region_list, "$start," . ( $bio_seq->length - $start );
            }
        }
        elsif ( $start < 0 ) {
            if ( ( $start + $length ) < 0 ) {
                $self->log->warn( 'Specified region is completely outside sequence' );
            }
            # This means the excluded region partially overlaps the sequence
            else {
                push @region_list,"0," . ( $length + $start );
            }
        }
        else {
            push @region_list,"$start,$length";
        }
    }

    return @region_list ? join( ' ', @region_list ) : undef;
}

__PACKAGE__->meta->make_immutable;

1;

__END__
