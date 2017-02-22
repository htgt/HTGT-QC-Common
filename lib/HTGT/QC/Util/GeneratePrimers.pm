package HTGT::QC::Util::GeneratePrimers;
## no critic(RequireUseStrict,RequireUseWarnings)
{
    $HTGT::QC::Util::GeneratePrimers::VERSION = '0.050';
}
## use critic


=head1 NAME

HTGT::QC::Util::GeneratePrimers

=head1 DESCRIPTION

Generate a primer pair for a given target.
Input:
    - Bio::Seq object with the target sequence
    - Coordinates of sequence in Bio::Seq object
    - Primer3 parameters
    - optional genomic specificifty check options

=cut

use Moose;
use MooseX::Types::Path::Class::MoreCoercions qw/AbsDir AbsFile/;
use Bio::SeqIO;
use Path::Class;
use DesignCreate::Util::Primer3;
use DesignCreate::Util::BWA;
use Try::Tiny;
use namespace::autoclean;
use Data::Dumper;
use JSON;

with qw( MooseX::Log::Log4perl );

has dir => (
    is       => 'ro',
    isa      => AbsDir,
    required => 1,
    coerce   => 1,
);

#
# Target Info
#

# target sequence
has bio_seq => (
    is       => 'ro',
    isa      => 'Bio::SeqI',
    required => 1,
);

# genomic start and end coordinates for the bio_seq
has [ 'region_start', 'region_end' ] => (
    is       => 'ro',
    isa      => 'Int',
    required => 1,
);

has species => (
    is       => 'ro',
    isa      => 'Str',
    required => 1,
);

# strand the target bio_seq belongs to
has strand => (
    is       => 'ro',
    isa      => 'Int',
    required => 1,
);

#
# Primer3 Parameters
#
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

=head2 primer3_target_string

String which tells Primer3 what region the primers must flank.
It is in the form: <start>,<length>
<start> is the index of the first base of the target region.
<length> is the the length of the target.

=cut
has primer3_target_string => (
    is       => 'ro',
    isa      => 'Str',
    required => 1,
);

=head2 primer_product_size_range

String which tells Primer3 what how big the product from the primers should be.
It is in the form: <x>-<y>
<x> is the minimum size
<y> is the maximum size

You can specify a list of ranges ( e.g. 100-200 400-500 ). If this is done Primer3 tries
to make produces in the first size range, only expanding to other ranges if it can't
find anything.

=cut
has primer_product_size_range => (
    is       => 'ro',
    isa      => 'Str',
    required => 1,
);

# hash of extra parameters we will send to DesignCreate::Util::Primer3
has additional_primer3_params => (
    is      => 'ro',
    isa     => 'HashRef',
    default => sub { {} },
);

#
# Genomic Specificity / BWA aln attributes
#

has check_genomic_specificity => (
    is      => 'ro',
    isa     => 'Bool',
    default => 1,
);

has num_bwa_threads => (
    is      => 'ro',
    isa     => 'Int',
    default => 1,
);

# Maximum number of genomic hits a oligos is allowed
has num_genomic_hits => (
    is      => 'ro',
    isa     => 'Int',
    default => 1,
);

has bwa_matches => (
    is      => 'rw',
    isa     => 'HashRef',
    traits  => [ 'NoGetopt' ],
    default => sub { {  } },
);

#
# Primer Storage
#

# Array of all the primer pairs found
has oligo_pairs => (
    is      => 'rw',
    isa     => 'ArrayRef',
    traits  => [ 'Array' ],
    handles => {
        add_oligo_pair   => 'push',
        have_oligo_pairs => 'count',
        all_oligo_pairs  => 'elements',
    }
);


# array of the valid primer pairs ( after genomic specificity check )
has valid_oligo_pairs => (
    is      => 'rw',
    isa     => 'ArrayRef',
    traits  => [ 'Array' ],
    default => sub { [] },
    handles => {
        add_valid_oligo_pair   => 'push',
        have_valid_oligo_pairs => 'count',
    }
);

=head2 generate_primers

Find primers for target region specified inside sequence.

=cut
sub generate_primers {
    my ( $self ) = @_;
    $self->log->info( 'Starting generate primers process' );

    my $result = $self->run_primer3;
    return unless $result;
    $self->parse_primer3_results( $result );

    if ( $self->check_genomic_specificity ) {
        $self->run_bwa;
        $self->filter_primers;

        if ( $self->have_valid_oligo_pairs ) {
            $self->log->info('Found oligo pair, passed genomic specificity check');
            return $self->valid_oligo_pairs;
        }
        else {
            $self->log->warn('Primer3 did not find any primer pairs');
            return;
        }
    }
    else {
        if ( $self->have_oligo_pairs ) {
            $self->log->info('Found oligo pair, not done genomic specificity check');
            return $self->oligo_pairs;

        }
        else {
            $self->log->warn('Primer3 did not find any primer pairs');
            return;
        }
    }

    return;
}

=head2 run_primer3

Run Primer3 using DesignCreate::Util::Primer3 module.

=cut
sub run_primer3 {
    my ( $self ) = @_;
    $self->log->debug( 'Running Primer3' );

    my %primer3_params = ( configfile => $self->primer3_config_file->stringify );
    $primer3_params{primer_product_size_range} = $self->primer_product_size_range;
    $primer3_params{primer3_task} = $self->primer3_task;

    # merge in any extra primer3 params
    my %extra_params = %{ $self->additional_primer3_params };
    for my $param_key ( keys %extra_params ) {
        $primer3_params{$param_key} = $extra_params{ $param_key }
            if $extra_params{ $param_key };
    }

    my $p3 = DesignCreate::Util::Primer3->new_with_config( %primer3_params );

    my $log_file = $self->dir->file( 'primer3_output.log' );
    my ( $result, $primer3_explain ) = $p3->run_primer3(
        $log_file->absolute,
        $self->bio_seq,
        {
            SEQUENCE_TARGET => $self->primer3_target_string,
        }
    );

    die( "Error running primer3, see logfile: $log_file" ) unless $result;

    # TODO is this all too complicated, could I just return $result?
    if ( $result->num_primer_pairs ) {
        $self->log->debug( "primer pairs found: " . $result->num_primer_pairs );
        return $result;
    }

    my $data = $result->persistent_data;
    # task defaults to pick_pcr_primers , for which we would want pairs
    if ( $self->primer3_task eq 'pick_left_only' && $data->{LEFT}{num_returned} ) {
        $self->log->debug( "Found left primers" );
        return $result;
    }
    elsif ( $self->primer3_task eq 'pick_right_only' && $data->{RIGHT}{num_returned} ) {
        $self->log->debug( "Found right primers" );
        return $result;
    }
    else {
        $self->log->warn( "Failed to generate primers" );
        return;
    }

    return;
}

=head2 parse_primer3_results

Extract the required information from the Bio::Tools::Primer3Redux::Result object
It outputs information about each primer pair.

=cut
sub parse_primer3_results {
    my ( $self, $result ) = @_;
    $self->log->debug( 'Parsing Primer3 results' );

    if ( $self->primer3_task eq 'pick_left_only' ) {
        while ( my $primer = $result->next_left_primer) {
            my $fwd_primer = $self->parse_primer( $primer, 'forward' );
            # store primer information, grouped in pairs
            $self->add_oligo_pair( { forward => $fwd_primer } );
        }
    }
    elsif ( $self->primer3_task eq 'pick_right_only' ) {
        while ( my $primer = $result->next_right_primer ) {
            my $rev_primer = $self->parse_primer( $primer, 'reverse' );
            # store primer information, grouped in pairs
            $self->add_oligo_pair( { reverse => $rev_primer } );
        }
    }
    else {
        while ( my $pair = $result->next_primer_pair ) {
            my $fwd_primer = $self->parse_primer( $pair->forward_primer, 'forward' );
            my $rev_primer = $self->parse_primer( $pair->reverse_primer, 'reverse' );
            # store primer information, grouped in pairs
            $self->add_oligo_pair( { forward => $fwd_primer, reverse => $rev_primer } );
        }
    }

    return;
}

=head2 parse_primer

Parse output required data from the Bio::Tools::Primer3Redux::Primer objects
( basically a Bio::SeqFeature::Generic object plus few other methods ).
Also add other calulated data about primer.

=cut
sub parse_primer {
    my ( $self, $primer, $direction ) = @_;

    my %oligo_data;
    my $primer_id   = $direction . '-' . $primer->rank;
    $oligo_data{id} = $primer_id;

    die( "primer3 failed to validate sequence for primer: $primer_id" )
        unless $primer->validate_seq;

    $self->calculate_oligo_coords_and_sequence( $primer, \%oligo_data, $direction );

    $oligo_data{oligo_length}    = $primer->length;
    $oligo_data{melting_temp}    = $primer->melting_temp;
    $oligo_data{gc_content}      = $primer->gc_content;
    $oligo_data{oligo_direction} = $direction;
    $oligo_data{rank}            = $primer->rank;

    return \%oligo_data;
}

=head2 calculate_oligo_coords_and_sequence

Primer3 takes in sequence 5' to 3' so we need to work out the primer
sequence and coordiantes if the target was on the +ve or -ve strand.

=cut
sub calculate_oligo_coords_and_sequence {
    my ( $self, $primer, $oligo_data, $direction ) = @_;

    $oligo_data->{target_region_start} = $self->region_start;
    $oligo_data->{target_region_end}   = $self->region_end;

    if ( $self->strand == 1 ) {
        $oligo_data->{oligo_start} = $self->region_start + $primer->start - 1;
        $oligo_data->{oligo_end}   = $self->region_start + $primer->end - 1;
        $oligo_data->{offset}      = $primer->start;
        $oligo_data->{oligo_seq}   = $primer->seq->seq;
    }
    else {
        $oligo_data->{oligo_start} = $self->region_end - $primer->end + 1;
        $oligo_data->{oligo_end}   = $self->region_end - $primer->start + 1;
        $oligo_data->{offset}
            = ( $self->region_end - $self->region_start + 1 ) - $primer->end;
        $oligo_data->{oligo_seq}   = $primer->seq->revcom->seq;
    }

    return;
}

=head2 filter_primers

Filter out primers that do not meet the genomic specificity criteria.
We have option of only picking forward / reverse primer so check if primer
exists first.

=cut
sub filter_primers {
    my ( $self ) = @_;
    $self->log->debug( 'Filtering primers of genomic specificity' );

    for my $oligo_pair ( $self->all_oligo_pairs ) {

        if ( exists $oligo_pair->{forward} ) {
            my $fwd_primer_id = $oligo_pair->{forward}{id};
            $self->check_oligo_specificity(
                $fwd_primer_id,
                $self->bwa_matches->{ $fwd_primer_id },
            ) or next;
        }

        if ( exists $oligo_pair->{reverse} ) {
            my $rev_primer_id = $oligo_pair->{reverse}{id};
            $self->check_oligo_specificity(
                $rev_primer_id,
                $self->bwa_matches->{ $rev_primer_id },
            ) or next;
        }

        $self->add_valid_oligo_pair( $oligo_pair );
    }

    return;
}

=head2 run_bwa

Run bwa aln against all the candidate primers.

=cut
sub run_bwa {
    my $self = shift;
    $self->log->debug( 'Running BWA aln' );

    my $bwa_query_file = $self->define_bwa_query_file;

    my $bwa = DesignCreate::Util::BWA->new(
        query_file        => $bwa_query_file,
        work_dir          => $self->dir,
        species           => $self->species,
        num_bwa_threads   => $self->num_bwa_threads,
    );

    try{
        $bwa->run_bwa_checks;
    }
    catch{
        die("Error running bwa " . $_);
    };

    $self->bwa_matches( $bwa->matches );

    return;
}

=head2 define_bwa_query_file

Generate a fasta file containing all the candidate primers to run against bwa aln.

=cut
sub define_bwa_query_file {
    my $self = shift;

    my $query_file = $self->dir->file('bwa_query.fasta');
    my $fh         = $query_file->openw or die( "Open $query_file: $!" );
    my $seq_out    = Bio::SeqIO->new( -fh => $fh, -format => 'fasta' );

    for my $oligo_pair ( $self->all_oligo_pairs ) {
        if ( exists $oligo_pair->{forward} ) {
            my $fwd_bio_seq = Bio::Seq->new(
                -seq => $oligo_pair->{forward}{oligo_seq},
                -id  => $oligo_pair->{forward}{id}
            );
            $seq_out->write_seq( $fwd_bio_seq );
        }

        if ( exists $oligo_pair->{reverse} ) {
            my $rev_bio_seq = Bio::Seq->new(
                -seq => $oligo_pair->{reverse}{oligo_seq},
                -id  => $oligo_pair->{reverse}{id}
            );
            $seq_out->write_seq( $rev_bio_seq );
        }
    }

    $self->log->debug("Created bwa query file $query_file");

    return $query_file;
}

=head2 check_oligo_specificity

Filter out oligos that have mulitple hits against the reference genome.
A unique alignment ( score of 30+ ) gives a true return value. This should be
the case where bwa finds one unique alignment for the oligo, which should be the
original position of the oligo, though this is not checked.

If the oligo can not be mapped against the genome we return false.

In any other case we count the number of hits, which is 90%+ similarity or up to 2 mismatches.
By default any more than 1 hit will return false, the user can loosen this criteria though
and allow up to n hits ( num_genomic_hits attribute ).

=cut
sub check_oligo_specificity {
    my ( $self, $oligo_id, $match_info ) = @_;
    # if we have no match info then fail oligo
    return unless $match_info;

    if ( exists $match_info->{unmapped} && $match_info->{unmapped} == 1 ) {
        $self->log->error( "Oligo $oligo_id does not have any alignments, is not mapped to genome" );
        return;
    }

    if ( exists $match_info->{unique_alignment} && $match_info->{unique_alignment} ) {
        $self->log->trace( "Oligo $oligo_id has a unique alignment");
        return 1;
    }

    die("No hits value for oligo $oligo_id, can not validate specificity")
        unless exists $match_info->{hits};
    my $hits = $match_info->{hits};

    if ( $hits <= $self->num_genomic_hits ) {
        $self->log->trace( "Oligo $oligo_id has $hits hits, user allowed " . $self->num_genomic_hits );
        return 1;
    }
    else {
        $self->log->debug( "Oligo $oligo_id is invalid, has multiple hits: $hits" );
        return;
    }

    return;
}

__PACKAGE__->meta->make_immutable;

1;

__END__
