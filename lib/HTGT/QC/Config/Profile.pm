package HTGT::QC::Config::Profile;

use Moose;
use MooseX::StrictConstructor;
use Parse::BooleanLogic;
use HTGT::QC::Exception;
use List::MoreUtils qw( uniq );
use namespace::autoclean;

has profile_name => (
    is       => 'ro',
    isa      => 'Str',
    required => 1
);

has alignment_regions => (
    is       => 'ro',
    isa      => 'HashRef',
    required => 1,
    traits   => [ 'Hash' ],
    handles  => {
        alignment_region    => 'get',
        is_alignment_region => 'exists'
    }
);

has primers => (
    isa      => 'HashRef',
    required => 1,
    traits   => [ 'Hash' ],
    handles  => {
        primers              => 'keys',
        condition_for_primer => 'get'
    }
);

has split_primers => (
    is      => 'rw',
    isa     => 'HashRef',
    traits  => [ 'Hash' ],
    default => sub { {} },
    handles => {
        add_split_primers  => 'set',
        get_split_primers  => 'get',
        has_split_primers => 'count',
        split_primer_exists => 'exists',
    },
);

has [ qw( pre_filter_min_score post_filter_min_primers ) ] => (
    is       => 'ro',
    isa      => 'Int',
    default  => 0
);

has pass_condition => (
    is       => 'ro',
    isa      => 'Str',
    required => 1
);

has primer_regions => (
    is         => 'ro',
    isa        => 'HashRef',
    lazy_build => 1,
    traits     => [ 'Hash' ],
    handles    => {
        regions_for_primer => 'get'
    }
);

# XXX Legacy attributes to support HTGTDB fetch/persist

has [ qw( apply_flp apply_cre apply_dre check_design_loc ) ] => (
    is      => 'ro',
    isa     => 'Bool',
    default => 0
);

has vector_stage => (
    is       => 'ro',
    isa      => 'Str',
    required => 1
);

# XXX END legacy attributes

sub _build_primer_regions {
    my $self = shift;

    my $parser = Parse::BooleanLogic->new();

    my %regions_for_primer;

    for my $primer_name ( $self->primers ) {
        my %regions;
        my $condition_str = $self->condition_for_primer( $primer_name );

        if ( ref $condition_str eq 'HASH' and exists $condition_str->{ 'split_into' } ) {
            $self->add_split_primers( $primer_name => $condition_str->{ 'split_into' } );

            next; #dont add a region for this, as we rename all reads with this name
        }

        $parser->as_array(
            $condition_str,
            operand_cb => sub {
                $regions{ $_[0] }++;
            }
        );
        my @regions = keys %regions;
        $self->assert_valid_regions( $primer_name, \@regions );
        $regions_for_primer{ $primer_name } = \@regions;
    }

    return \%regions_for_primer;
}

sub BUILD {
    my $self = shift;

    # Ensure the builder runs on object creation
    $self->primer_regions;
    return;
}

sub assert_valid_regions {
    my ( $self, $primer_name, $regions ) = @_;

    HTGT::QC::Exception->throw( "No regions defined for primer '$primer_name'" )
            unless @{$regions};

    for my $region_name ( @{$regions} ) {
        unless ( $self->is_alignment_region( $region_name ) ) {
            HTGT::QC::Exception->throw( "Alignment region '$region_name' for primer '$primer_name' is not defined" );
        }
    }
    return;
}

sub expected_strand_for_primer {
    my ( $self, $primer ) = @_;

    my @strands;
    for my $region_name ( @{ $self->regions_for_primer( $primer ) } ) {
        my $region = $self->alignment_region( $region_name );
        push @strands, $region->{expected_strand};
    }

    @strands = uniq( @strands );

    if ( @strands != 1 ) {
        HTGT::QC::Exception->throw( 'Found ' . @strands . ' expected strands for ' . $primer . ' (expected 1)' );
    }

    return $strands[0];
}

sub is_primer_pass {
    my ( $self, $primer, $alignments ) = @_;

    my $callback = sub {
        my $region = $_[0]->{operand};
        exists $alignments->{$region} && $alignments->{$region}{pass};
    };

    my $parser = Parse::BooleanLogic->new;
    return $parser->solve( $parser->as_array( $self->condition_for_primer( $primer ) ), $callback );
}

sub is_pass {
    my ( $self, $primer_results ) = @_;

    my $callback = sub {
        my $primer = $_[0]->{operand};
        exists $primer_results->{$primer} && $primer_results->{$primer}{pass};
    };

    my $parser = Parse::BooleanLogic->new;
    return $parser->solve( $parser->as_array( $self->pass_condition ), $callback );
}

sub is_genomic_pass {
    my ( $self, $primer_results ) = @_;

    if ( $primer_results->{alignment} ) {
        while ( my ( $region, $analysis ) = each %{ $primer_results->{alignment} } ) {
            return 1 if $analysis->{pass} && $self->alignment_region( $region )->{genomic};
        }
    }

    return 0;
}

sub is_es_cell {
    my ( $self ) = @_;

    return $self->vector_stage eq 'allele';
}

__PACKAGE__->meta->make_immutable;

1;

__END__
