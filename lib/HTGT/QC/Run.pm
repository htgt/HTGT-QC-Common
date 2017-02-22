package HTGT::QC::Run;
## no critic(RequireUseStrict,RequireUseWarnings)
{
    $HTGT::QC::Run::VERSION = '0.050';
}
## use critic


use strict;
use warnings FATAL => 'all';

use Moose;
use Moose::Util::TypeConstraints;
use MooseX::Params::Validate;
use MooseX::Types::Path::Class;
use Data::UUID;
use YAML;
use namespace::autoclean;
use HTGT::QC::Util::FileAccessServer;

with qw( MooseX::Log::Log4perl );

has id => (
    is       => 'ro',
    isa      => 'Str',
    required => 1
);

has config => (
    is       => 'ro',
    isa      => 'HTGT::QC::Config',
    required => 1,
    handles  => [ qw( software_version ) ]
);

has profile => (
    is       => 'ro',
    isa      => 'Str',
    required => 1
);

has template_plate => (
    is       => 'ro',
    isa      => 'Str',
    required => 1
);

has sequencing_projects => (
    is       => 'ro',
    isa      => 'ArrayRef',
    required => 1
);

has workdir => (
    is       => 'ro',
    isa      => 'Path::Class::Dir',
    required => 1
);

has run_type => (
    is     => 'ro',
    isa    => enum( [ qw( vector es_cell prescreen ) ] ),
    required => 1,
);

has plate_map => (
    is      => 'ro',
    isa     => 'HashRef',
    default => sub{ {} },
);

has created_by => (
    is       => 'ro',
    isa      => 'Str',
    required => 0,
);

has species => (
    is       => 'ro',
    isa      => 'Str',
    required => 0,
);


has file_api => (
    is    => 'ro',
    isa   => 'HTGT::QC::Util::FileAccessServer',
    lazy_build => 1,
);

sub _build_file_api{
    my $lustre_server = $ENV{ FILE_API_URL }
        or die "FILE_API_URL environment variable not set";
    return HTGT::QC::Util::FileAccessServer->new({ file_api_url => $lustre_server });
}
sub init {
    my $class = shift;

    #plate_map is required for vector, should perhaps enforce that?

    my %params = validated_hash(
        \@_,
        config              => { isa => 'HTGT::QC::Config' },
        profile             => { isa => 'Str' },
        template_plate      => { isa => 'Str' },
        sequencing_projects => { isa => 'ArrayRef' },
        run_type            => { isa => 'Str' },
        persist             => { isa => 'Bool', default => 1 },
        plate_map           => { isa => 'HashRef', optional => 1 },
        created_by          => { isa => 'Str', optional => 1 },
        species             => { isa => 'Str', optional => 1 },
    );

    $params{id}       = Data::UUID->new->create_str;
    $params{workdir}  = $params{config}->basedir->subdir( $params{id} );

    my $self = $class->new( \%params );

    $self->init_workdir();

    $self->log->info( 'Initialized QC job ' . $self->id );

    return $self;
}

sub init_workdir {
    my ( $self, $params ) = @_;

    my $dir = $self->workdir;

    $self->file_api->make_dir("$dir");

    # Persist parameters required for restore
    my $yaml = Dump(
        {
            profile             => $self->profile,
            template_plate      => $self->template_plate,
            sequencing_projects => $self->sequencing_projects,
            plate_map           => $self->plate_map,
            created_by          => $self->created_by,
            species             => $self->species,
        }
    );

    $self->file_api->post_file_content($self->workdir->file( 'params.yaml' ),$yaml);

    return;
}

__PACKAGE__->meta->make_immutable;

1;

__END__
