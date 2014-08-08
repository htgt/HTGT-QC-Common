package HTGT::QC::Util::GeneratePrimersAttempts;

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

with qw(
MooseX::Log::Log4perl
DesignCreate::Role::EnsEMBL
);

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

#
# Primer3 Parameters
#

has primer3_config_file => (
    is       => 'ro',
    isa      => AbsFile,
    required => 1,
);

# any additional parameters not specified in primer3 config file
has additional_primer3_params => (
    is      => 'ro',
    isa     => 'HashRef',
    default => sub{ {} },
);

# set custom primer product size ranges, normally we can work it out
has primer_product_size_range => (
    is  => 'ro',
    isa => 'Int',
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

=head2 find_primers

Attempt to generate primers for target, if this fails initially try again
with a increased search area for the primers.

=cut
sub find_primers {
    my ( $self ) = @_;
    $self->log->info( 'ATTEMPT ' . $self->current_attempt . ' at primer generation' );

    my $primers;
    $primers = $self->generate_primer_attempt;
    while ( !$primers && $self->current_attempt < $self->retry_attempts ) {
        $self->setup_new_attempt;
        $self->log->info( '--------' );
        $self->log->info( 'ATTEMPT ' . $self->current_attempt . ' at primer generation' );
        $primers = $self->generate_primer_attempt;
    }
    return $primers;
}

=head2 generate_primer_attempt

Run the HTGT::QC::Util::GeneratePrimers modules.

=cut
sub generate_primer_attempt {
    my ( $self ) = @_;

    my $start = $self->target_start - $self->five_prime_region_size;
    my $end   = $self->target_end + $self->three_prime_region_size;
    my $seq_slice = $self->build_region_slice( $start, $end );
    my $bio_seq = Bio::Seq->new( -display_id => 'primer_search_region', -seq => $seq_slice->seq );

    my $work_dir = $self->base_dir->subdir( $self->current_attempt );
    $work_dir->mkpath;
    my $target_string = $self->generate_target_string;
    my $primer_product_size_range = $self->primer_product_size_range
        || $self->generate_primer_product_size_range( $start, $end );

    my $util = HTGT::QC::Util::GeneratePrimers->new(
        dir                       => $work_dir,
        bio_seq                   => $bio_seq,
        region_start              => $start,
        region_end                => $end,
        species                   => $self->species,
        strand                    => $self->strand,
        primer3_config_file       => $self->primer3_config_file,
        primer3_target_string     => $target_string,
        primer_product_size_range => $primer_product_size_range,
        additional_primer3_params => $self->additional_primer3_params,
    );

    my $primer_data;
    try {
        $primer_data = $util->generate_primers;
    }
    catch {
        $self->log->error("Problem running GeneratePrimers: $_");
    };

    return $primer_data;
}

=head2 setup_new_attempt

Expand primer search region.

=cut
sub setup_new_attempt {
    my ( $self ) = @_;

    $self->current_attempt( $self->current_attempt + 1 );
    $self->log->info( 'Last attempt failed, expanding primer search region' );

    $self->five_prime_region_size( $self->five_prime_region_size + $self->primer_search_region_expand );
    $self->three_prime_region_size( $self->three_prime_region_size + $self->primer_search_region_expand );

    return;
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

You can specify a list of ranges ( e.g. 100-200,400-500 )
This is the PRIMER_PRODUCT_SIZE_RANGE parameter sent into Primer3.

=cut
sub generate_primer_product_size_range {
    my ( $self, $start, $end ) = @_;

    my $min_size = $self->target_end - $self->target_start;
    my $max_size = $end - $start;
    my $primer_product_size_range = $min_size . '-' . $max_size;
    $self->log->debug( "Primer produect size range string: $primer_product_size_range" );

    return $primer_product_size_range;
}

=head2 build_region_slice

Build a Bio::EnsEMBL::Slice for a given target regions

=cut
sub build_region_slice {
    my ( $self, $start, $end ) = @_;

    my $slice = $self->ensembl_util->get_repeat_masked_slice(
        $start, $end, $self->chromosome,
        $self->no_repeat_mask_classes ? undef : $self->repeat_mask_class
    );

    # primer3 expects sequence in a 5' to 3' direction, so reverse compliment if
    # target is on the -ve strand
    return $self->strand == 1 ? $slice : $slice->invert;
}

__PACKAGE__->meta->make_immutable;

1;

__END__
