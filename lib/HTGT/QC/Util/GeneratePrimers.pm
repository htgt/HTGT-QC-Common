package HTGT::QC::Util::GeneratePrimers;

=head1 NAME

HTGT::QC::Util::GeneratePrimers

=head1 DESCRIPTION

Generate a primer pair for a given target.

=cut

use Moose;
use MooseX::Types::Path::Class::MoreCoercions qw/AbsDir AbsFile/;
use Bio::SeqIO;
use Path::Class;
use DesignCreate::Util::Primer3;
use DesignCreate::Util::BWA;
use Try::Tiny;
use namespace::autoclean;

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

has bio_seq => (
    is       => 'ro',
    isa      => 'Bio::SeqI',
    required => 1,
);

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

has strand => (
    is       => 'ro',
    isa      => 'Int',
    required => 1,
);

#
# Primer3 Parameters
#

has primer3_config_file => (
    is       => 'ro',
    isa      => AbsFile,
    required => 1,
);

has primer3_target_string => (
    is       => 'ro',
    isa      => 'Str',
    required => 1,
);

has primer_product_size_range => (
    is       => 'ro',
    isa      => 'Str',
    required => 1,
);

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

desc

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

Possible additional attributes to send to Primer3 Runner
These will mostly be fixed...
    'primer_num_return',
    'primer_min_size',
    'primer_max_size',
    'primer_opt_size',
    'primer_opt_gc_percent',
    'primer_max_gc',
    'primer_min_gc',
    'primer_opt_tm',
    'primer_max_tm',
    'primer_min_tm',
    'primer_lowercase_masking',
    'primer_explain_flag',
    'primer_min_three_prime_distance',
    'primer_product_size_range',
    'primer_thermodynamic_parameters_path',
    'primer_gc_clamp',

=cut
sub run_primer3 {
    my ( $self ) = @_;
    $self->log->debug( 'Running Primer3' );

    my %primer3_params = ( configfile => $self->primer3_config_file->stringify );
    $primer3_params{primer_product_size_range} = $self->primer_product_size_range;

    # merge in any extra primer3 params
    my %extra_params = %{ $self->additional_primer3_params };
    if ( %extra_params ) {
        @primer3_params{ keys %extra_params } = values %extra_params;
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

    if ( $result->num_primer_pairs ) {
        $self->log->debug( "primer pairs found: " . $result->num_primer_pairs );
    }
    else {
        # TODO info from $primer3_explain?
        $self->log->warn( "Failed to generate primer pairs" );
        return;
    }

    return $result;
}

=head2 parse_primer3_results

Extract the required information from the Bio::Tools::Primer3Redux::Result object
It outputs information about each primer pair.

=cut
sub parse_primer3_results {
    my ( $self, $result ) = @_;
    $self->log->debug( 'Parsing Primer3 results' );

    while ( my $pair = $result->next_primer_pair ) {
        my $forward_primer = $self->parse_primer( $pair->forward_primer, 'forward' );
        my $reverse_primer = $self->parse_primer( $pair->reverse_primer, 'reverse' );

        # store primer information, grouped in pairs
        $self->add_oligo_pair(
            {   forward => $forward_primer,
                reverse => $reverse_primer,
            }
        );
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

Primer3 takes in sequence 5' to 3' so we need to work out the sequence in the
+ve strand plus its coordinates

=cut
sub calculate_oligo_coords_and_sequence {
    my ( $self, $primer, $oligo_data, $direction ) = @_;

    $oligo_data->{target_region_start} = $self->region_start;
    $oligo_data->{target_region_end}   = $self->region_end;

    # TODO check how primers stored in LIMS2, always 5' to 3'?
    #      if not then all the below has to change
    if ( $self->strand == 1 ) {
        $oligo_data->{oligo_start} = $self->region_start + $primer->start - 1;
        $oligo_data->{oligo_end}   = $self->region_start + $primer->end - 1;
        $oligo_data->{offset}      = $primer->start;
        $oligo_data->{oligo_seq}
            = $direction eq 'forward' ? $primer->seq->seq : $primer->seq->revcom->seq;
    }
    else {
        $oligo_data->{oligo_start} = $self->region_end - $primer->end + 1;
        $oligo_data->{oligo_end}   = $self->region_end - $primer->start + 1;
        $oligo_data->{offset}
            = ( $self->region_end - $self->region_start + 1 ) - $primer->end;
        $oligo_data->{oligo_seq}
            = $direction eq 'forward' ? $primer->seq->revcom->seq : $primer->seq->seq;
    }

    return;
}

=head2 filter_primers

desc

=cut
sub filter_primers {
    my ( $self ) = @_;
    $self->log->debug( 'Filtering primers of genomic specificity' );

    for my $oligo_pair ( $self->all_oligo_pairs ) {

        my $fwd_primer_id = $oligo_pair->{forward}{id};
        $self->check_oligo_specificity(
            $fwd_primer_id,
            $self->bwa_matches->{ $fwd_primer_id },
        ) or next;

        my $rev_primer_id = $oligo_pair->{reverse}{id};
        $self->check_oligo_specificity(
            $rev_primer_id,
            $self->bwa_matches->{ $rev_primer_id },
        ) or next;

        $self->add_valid_oligo_pair( $oligo_pair );
    }

    return;
}

=head2 run_bwa


=cut
sub run_bwa {
    my $self = shift;
    $self->log->debug( 'Running BWA aln' );

    my $bwa_query_file = $self->define_bwa_query_file;

    my $bwa = DesignCreate::Util::BWA->new(
        query_file        => $bwa_query_file,
        work_dir          => $self->dir, #TODO this ok?
        species           => $self->species,
        num_bwa_threads   => $self->num_bwa_threads,
    );

    try{
        $bwa->run_bwa_checks;
    }
    catch{
        #TODO need this?
        die("Error running bwa " . $_);
    };

    $self->bwa_matches( $bwa->matches );

    return;
}

=head2 define_bwa_query_file

=cut
sub define_bwa_query_file {
    my $self = shift;

    my $query_file = $self->dir->file('bwa_query.fasta');
    my $fh         = $query_file->openw or die( "Open $query_file: $!" );
    my $seq_out    = Bio::SeqIO->new( -fh => $fh, -format => 'fasta' );

    for my $oligo_pair ( $self->all_oligo_pairs ) {
        my $fwd_bio_seq = Bio::Seq->new(
            -seq => $oligo_pair->{forward}{oligo_seq},
            -id  => $oligo_pair->{forward}{id}
        );
        $seq_out->write_seq( $fwd_bio_seq );

        my $rev_bio_seq = Bio::Seq->new(
            -seq => $oligo_pair->{reverse}{oligo_seq},
            -id  => $oligo_pair->{reverse}{id}
        );
        $seq_out->write_seq( $rev_bio_seq );
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
