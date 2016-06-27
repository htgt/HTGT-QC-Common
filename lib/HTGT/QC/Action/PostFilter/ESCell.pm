package HTGT::QC::Action::PostFilter::ESCell;

use Moose;
use MooseX::ClassAttribute;
use MooseX::Types::Path::Class;
use Path::Class;
use YAML::Any;
use HTGT::QC::Exception;
use List::MoreUtils qw( any );
use namespace::autoclean;

extends qw( HTGT::QC::Action );

override command_names => sub {
    'post-filter-es-cell'
};

override abstract => sub {
    'run post-filter for ES cell QC'
};

has output_dir => (
    is       => 'ro',
    isa      => 'Path::Class::Dir',
    traits   => [ 'Getopt' ],
    cmd_flag => 'output-dir',
    required => 1,
    coerce   => 1
);

sub execute {
    my ( $self, $opts, $args ) = @_;

    $self->log->debug( "Running post_filter" );

    my $analysis = $self->parse_analysis( $args );

    for my $well_name ( keys %{$analysis} ) {
        for my $target_id ( keys %{ $analysis->{$well_name} } ){
            my @results = map values %$_, values %{ $analysis->{$well_name}{$target_id} };
            unless ( any { $self->profile->is_genomic_pass($_) } @results ) {
                delete $analysis->{$well_name}{$target_id};
            }
        }
        if ( keys %{ $analysis->{$well_name} } > 0 ) {
            $self->write_analysis( $well_name, $analysis->{$well_name} );            
        }
    }

    #if the ouput_dir doesn't exist then nothing passed the post-filter.
    unless ( -e $self->output_dir ) {
        $self->log->debug( "Post filter failed: no results." ); #display to the user
        die "Post filter failed.";
    }
}

sub write_analysis {
    my ( $self, $well_name, $analysis ) = @_;

    my $this_out_dir = $self->output_dir->subdir( $well_name );
    $this_out_dir->mkpath;

    while ( my ( $target_id, $target_analysis ) = each %{$analysis} ) {
        my $this_out_file = $this_out_dir->file( $target_id . '.yaml' );
        my %this_analysis = (
            query_well => $well_name,
            target_id  => $target_id,
            primers    => $self->collapse_primers( $target_analysis )
        );
        YAML::Any::DumpFile( $this_out_file, \%this_analysis );
    }
}

sub collapse_primers {
    my ( $self, $analysis ) = @_;

    my %collapsed;
    for my $plate_type ( keys %{$analysis} ) {
        while ( my ( $primer, $primer_result ) = each %{ $analysis->{$plate_type} } ) {
            $primer = $plate_type ? $plate_type . '_' . $primer : $primer;            
            $primer_result->{primer} = $primer;
            $collapsed{$primer} = $primer_result;
        }
    }

    return \%collapsed;
}

sub parse_analysis {
    my ( $self, $analysis_dirs ) = @_;

    my %analysis;
    
    for my $analysis_dir ( map dir($_), @{$analysis_dirs} ) {
        for my $query_dir ( $analysis_dir->children ) {
            for my $target_yaml ( $query_dir->children ) {
                my $target_analysis = YAML::Any::LoadFile( $target_yaml );
                my ( $plate_name, $plate_type, $well_name );
                if ( $self->is_lims2 ) {
                    ( $plate_name, $well_name ) = $target_analysis->{query_well} =~ qr/^(.+)_(?:_\d)*(?:\d)*([a-zA-Z]\d{2})$/;
                    $plate_type = '';
                }
                else {
                    ( $plate_name, $plate_type, $well_name ) = $target_analysis->{query_well} =~ qr/^(.+)_([ABRZ])(?:_\d)*(?:\d)*([a-zA-Z]\d{2})$/;
                }

                HTGT::QC::Exception->throw( "failed to parse plate_id/type/well from $target_analysis->{ query_well }" )
                    unless $plate_name and $well_name;

                for my $p ( values %{ $target_analysis->{primers} } ) {
                    $analysis{ $plate_name . $well_name }{ $target_analysis->{target_id} }{ $plate_type }{ $p->{ primer } } = $p;
                }
            }
        }
    }

    return \%analysis;
}    

__PACKAGE__->meta->make_immutable;

1;

__END__
