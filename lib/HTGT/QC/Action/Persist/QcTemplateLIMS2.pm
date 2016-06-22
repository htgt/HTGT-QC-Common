package HTGT::QC::Action::Persist::QcTemplateLIMS2;

use Moose;
use Try::Tiny;
use YAML::Any;
use namespace::autoclean;

extends qw( HTGT::QC::Action );
with qw( HTGT::QC::Util::LIMS2Client );

override command_names => sub {
    'persist-template-lims2'
};

override abstract => sub {
    'persist qc template plate to LIMS2 database'
};

has output_file => (
    is       => 'ro',
    isa      => 'Path::Class::File',
    coerce   => 1,
    required => 1,
    traits   => [ 'Getopt' ],
    cmd_flag => 'output-file',
);

sub execute {
    my ( $self, $opts, $args ) = @_;

    my $template_data = YAML::Any::LoadFile( $args->[0] );

    my $lims2_qc_template;
    try {
        $lims2_qc_template = $self->lims2_client->POST( 'qc_template', $template_data );
    }
    catch {
        HTGT::QC::Exception->throw( "Failed to persist qc_template plate to lims2 :" . $_ );
    };

    YAML::Any::DumpFile( $self->output_file, $lims2_qc_template );
}

1;

__END__
