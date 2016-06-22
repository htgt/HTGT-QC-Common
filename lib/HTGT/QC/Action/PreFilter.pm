package HTGT::QC::Action::PreFilter;

use Moose;
use MooseX::Types::Path::Class;
use HTGT::QC::Util::CigarParser;
use Path::Class;
use List::Util qw( reduce );
use YAML::Any;
use namespace::autoclean;

extends qw( HTGT::QC::Action );

has output_file => (
    is       => 'ro',
    isa      => 'Path::Class::File',
    coerce   => 1,
    required => 1,
    traits   => [ 'Getopt' ],
    cmd_flag => 'output-file',
);

has plate_name_map => (
    is       => 'ro',
    isa      => 'HashRef',
    traits   => [ 'Getopt' ],
    cmd_flag => 'plate-map',
    default  => sub{ {} },
);

sub execute {
    my ( $self, $opts, $args ) = @_;

    $self->log->info( "Running pre_filter" );

    $self->log->debug( "Primers: " . join q{,}, $self->profile->primers );
    
    my $it = HTGT::QC::Util::CigarParser->new(
        primers   => $self->config->all_primers,
        plate_map => $self->plate_name_map
    )->file_iterator( @{$args} );
    
    my %alignments_for;

    while ( my $cigar = $it->next ) {
        push @{ $alignments_for{ $cigar->{query_well} }{ $cigar->{target_id} } }, $cigar;
    }

    my @filtered;

    for my $query_well ( sort keys %alignments_for ) {
        Log::Log4perl::NDC->push( $query_well );
        for my $target_id ( sort keys %{ $alignments_for{$query_well} } ) {
            Log::Log4perl::NDC->push( $target_id );
            my $cigars = $alignments_for{$query_well}{$target_id};
            my $best_reads = $self->best_reads_per_primer( $cigars );
            if ( $self->is_wanted( $best_reads ) ) {
                push @filtered, values %{$best_reads};
            }
            Log::Log4perl::NDC->pop;
        }
        Log::Log4perl::NDC->pop;
    }   

    YAML::Any::DumpFile( $self->output_file, \@filtered );
}

sub is_wanted {
    HTGT::QC::Exception->throw( "is_wanted() must be implemented by a subclass" );
}

sub best_reads_per_primer {
    my ( $self, $cigars ) = @_;

    # Group by primer
    my %cigars_for_primer;
    for my $cigar ( @{$cigars} ) {
        push @{ $cigars_for_primer{ $cigar->{query_primer} } }, $cigar;
    }

    my %profile_primers = map{ $_ => 1 } $self->profile->primers;

    # Now pick the highest-scoring read for each primer
    my %best_read_for_primer;
    for my $primer ( keys %cigars_for_primer ) {
        unless ( exists $profile_primers{$primer} ) {
            $self->log->warn( "Primer $primer found but not defined in qc profile" );
            next;
        }
        my $expected_strand = $self->profile->expected_strand_for_primer( $primer )
            or HTGT::QC::Exception->throw( "Cannot determine expected strand for $primer" );
        my @cigars = grep { $_->{target_strand} eq $expected_strand } @{ $cigars_for_primer{$primer} };        
        unless ( @cigars ) {
            $self->log->warn( "No alignments for $primer on expected strand" );
            @cigars = @{ $cigars_for_primer{$primer} };            
        }
        $best_read_for_primer{$primer} = reduce { $a->{score} > $b->{score} ? $a : $b } @cigars;
    }

    return \%best_read_for_primer;
}

__PACKAGE__->meta->make_immutable;

1;

__END__
