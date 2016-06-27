package HTGT::QC::Action::FetchTemplateData::LIMS2;

use Moose;
use namespace::autoclean;

extends qw( HTGT::QC::Action::FetchTemplateData );
with qw( HTGT::QC::Util::LIMS2Client );

override command_names => sub {
    'fetch-template-data-lims2'
};

override abstract => sub {
    'fetch engineered sequence params for the specified LIMS2 template plate'
};

sub get_eng_seq_params {
    my ( $self, $plate_name ) = @_;

    my $params = $self->lims2_client->GET( 'qc_template', { name => $plate_name } );
    
    # GET method returns a single HashRef within an ArrayRef
    # we only want the HashRef
    return $params->[0];
}

__PACKAGE__->meta->make_immutable;

1;

__END__
