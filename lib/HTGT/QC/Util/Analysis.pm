package HTGT::QC::Util::Analysis;

use strict;
use warnings FATAL => 'all';

use Moose;
use MooseX::Types::Path::Class;
use namespace::autoclean;

use HTGT::QC::Util::FindSeq;
use HTGT::QC::Util::FindSeqFeature ();
use HTGT::QC::Util::AnalyzeAlignment qw( analyze_alignment );
use Bio::SeqIO;
use Path::Class;
use List::Util qw( max );
use List::MoreUtils qw( all );
use Iterator::Simple ();
use Parse::BooleanLogic;
use Data::Dump 'pp';
use YAML::Any;
use Try::Tiny;

with 'MooseX::Log::Log4perl';

has alignments_file => (
    is       => 'ro',
    isa      => 'Path::Class::File',
    required => 1,
    coerce   => 1
);

has [ qw( synvec_dir output_dir ) ] => (
    is       => 'ro',
    isa      => 'Path::Class::Dir',
    required => 1,
    coerce   => 1
);

has profile => (
    is       => 'ro',
    isa      => 'HTGT::QC::Config::Profile',
    required => 1,
    handles  => [ 'check_design_loc' ]
);

has sequence_reads => (
    is            => 'ro',
    isa           => 'HashRef[Bio::SeqI]',
    required      => 1,
    traits        => [ 'Hash' ],
    handles       => {
        get_sequence_read => 'get'
    }
);

has expected_design_loc => (
    is         => 'ro',
    isa        => 'HashRef',
    traits     => [ 'Hash' ],
    handles    => {
        expected_design_for => 'get'
    },
    lazy_build => 1
);

around get_sequence_read => sub {
    my $orig = shift;
    my $self = shift;
    my $read_id = shift;

    $self->log->debug( "get_sequence_read: " . $read_id );
    my $read = $self->$orig( $read_id );
    if ( ! $read ) {
        HTGT::QC::Exception->throw( "Failed to retrieve sequenec read $read_id" );        
    }

    return $read;
};

has template_params => (
    is       => 'ro',
    isa      => 'HashRef',
    required => 0,
);

has eng_seq_design_ids => (
    is         => 'ro',
    isa        => 'HashRef',
    traits     => [ 'Hash' ],
    lazy_build => 1,
    handles => {
        design_id_for_eng_seq => 'get',
    }
);

sub _build_eng_seq_design_ids {
    my $self = shift;
    my %eng_seq_design_ids;

    foreach my $well_name ( keys %{ $self->template_params->{wells} } ) {
        my $well_params = $self->template_params->{wells}{$well_name};
        my $eng_seq_id = $well_params->{eng_seq_id};
        my $design_id = $well_params->{eng_seq_params}{design_id};
        $eng_seq_design_ids{$eng_seq_id} = $design_id;
    }

    return \%eng_seq_design_ids;
}

sub BUILD {
    my $self = shift;

    HTGT::QC::Exception->throw( 'template plate params must be specified when check_design_loc is requested' )
            if $self->check_design_loc and not defined $self->template_params;    
}

sub analyze_all {
    my $self = shift;

    my $alignments = $self->alignments_iterator;

    my $cigar = $alignments->next;

    while ( $cigar ) {        
        my $query_well  = $cigar->{query_well};
        my $target_id   = $cigar->{target_id};
        my @cigars      = ();        
        while ( $cigar and $cigar->{query_well} eq $query_well
                    and $cigar->{target_id} eq $target_id ) {
            push @cigars, $cigar;
            $cigar = $alignments->next;
        }
        $self->analyze_pair( $query_well, $target_id, \@cigars );
    }
}

sub analyze_pair {
    my ( $self, $query_well, $target_id, $cigars ) = @_;
    
    $self->log->info( "Running analysis for $query_well/$target_id" );

    my $target = $self->get_synvec( $target_id );

    my %analysis = ( query_well => $query_well, target_id => $target_id );

    for my $cigar ( @{$cigars} ) {
        try {
            my $query = $self->get_sequence_read( $cigar->{query_id} );
            my $primer = $cigar->{query_primer}
                or die "failed to parse primer name from cigar: '$cigar->{raw}'";            
            my $this_alignment = analyze_alignment( $target, $query, $cigar, $self->profile );
            $analysis{primers}{ $this_alignment->{primer} } = $this_alignment;
        }
        catch {
            $self->log->error( $_ );
        };
    }

    if ( $self->check_design_loc ) {        
        my $well_name = uc substr( $query_well, -3 );
        $analysis{expected_design} = $self->expected_design_for( $well_name );
        $analysis{observed_design} = $self->design_id_for_eng_seq( $target_id );
        $analysis{pass} = $self->profile->is_pass( $analysis{primers} )
            && defined $analysis{expected_design}
                && defined $analysis{observed_design}
                    && $analysis{expected_design} == $analysis{observed_design};
    }    
    else {
        $analysis{pass} = $self->profile->is_pass( $analysis{primers} )
    }
    
    $self->log->info( "$query_well/$target_id: " . ( $analysis{pass} ? 'pass' : 'fail' ) );
    
    $self->write_analysis( $query_well, $target_id, \%analysis );
}

sub get_synvec {
    my ( $self, $synvec_id ) = @_;

    find_seq( $self->synvec_dir, $synvec_id, 'genbank' );
}

sub alignments_iterator {
    my $self = shift;

    my $alignments = YAML::Any::LoadFile( $self->alignments_file );
    
    return Iterator::Simple::iter( $alignments );
}

sub write_analysis {
    my ( $self, $query_well, $target_id, $analysis ) = @_;

    my $output_file = $self->output_dir->subdir( $query_well )->file( "$target_id.yaml" );
    $self->log->debug( "Writing analysis to $output_file" );
    $output_file->dir->mkpath;

    YAML::Any::DumpFile( $output_file, $analysis );
}

sub _build_expected_design_loc {
    my $self = shift;

    my %design_loc_for;

    for my $well_name ( keys %{ $self->template_params->{wells} } ) {
        my $design_id = $self->template_params->{wells}{$well_name}{eng_seq_params}{design_id};
        $design_loc_for{ $well_name } = $design_id;
    }

    return \%design_loc_for;
}

__PACKAGE__->meta->make_immutable;

1;

__END__
