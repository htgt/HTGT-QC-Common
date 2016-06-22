package HTGT::QC::Action::Persist::LIMS2QcRun;

use Moose;
use YAML::Any;
use Try::Tiny;
use namespace::autoclean;

extends qw( HTGT::QC::Action );
with qw( HTGT::QC::Util::LIMS2Client );

override command_names => sub {
    'persist-lims2-qc-run'
};

override abstract => sub {
    'persist qc run to LIMS2 database'
};

has lims2_template_file => (
    is       => 'ro',
    isa      => 'Path::Class::File',
    traits   => [ 'Getopt' ],
    cmd_flag => 'lims2-template-file',
    coerce   => 1,
    required => 1,
);

has qc_run_id => (
    is       => 'ro',
    isa      => 'Str',
    traits   => [ 'Getopt' ],
    cmd_flag => 'run-id',
    required => 1
);

has sequencing_projects => (
    isa      => 'ArrayRef[Str]',
    traits   => [ 'Getopt', 'Array' ],
    cmd_flag => 'sequencing-project',
    required => 1,
    handles  => {
        sequencing_projects => 'elements'
    }
);        

has qc_template_id => (
    is         => 'ro',
    isa        => 'Int',
    traits     => [ 'NoGetopt' ],
    lazy_build => 1,
);

has created_by => (
    is         => 'ro',
    isa        => 'Str',
    traits     => [ 'Getopt' ],
    cmd_flag   => 'created-by',
    required   => 1,
);

has species => (
    is         => 'ro',
    isa        => 'Str',
    traits     => [ 'Getopt' ],
    cmd_flag   => 'species',
    required   => 1,
);

sub _build_qc_template_id {
    my $self = shift;

    my $qc_template_data = YAML::Any::LoadFile( $self->lims2_template_file );
    return $qc_template_data->{id};
}

sub execute {
    my ( $self, $opts, $args ) = @_;

    $self->log->debug( "Create QCRun: " . $self->qc_run_id );

    try{
        $self->lims2_client->POST( 'qc_run', 
            {
                id                     => $self->qc_run_id,
                created_by             => $self->created_by,
                profile                => $self->profile_name,
                software_version       => $self->config->software_version,
                qc_template_id         => $self->qc_template_id,
                qc_sequencing_projects => [ $self->sequencing_projects ],
                species                => $self->species,
            }
        );
    }
    catch {
        HTGT::QC::Exception->throw( 'Error persisting qc_run data to LIMS2 for qc_run '
            . $self->qc_run_id . ' : ' . $_ );
    };
}

1;

__END__
