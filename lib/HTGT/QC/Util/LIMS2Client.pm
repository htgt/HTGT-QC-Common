package HTGT::QC::Util::LIMS2Client;
## no critic(RequireUseStrict,RequireUseWarnings)
{
    $HTGT::QC::Util::LIMS2Client::VERSION = '0.050';
}
## use critic


use Moose::Role;
use LIMS2::REST::Client;
use namespace::autoclean;

has lims2_client => (
    is         => 'ro',
    isa        => 'LIMS2::REST::Client',
    lazy_build => 1,
    traits     => [ 'NoGetopt' ]
);

has lims2_client_conffile => (
    is         => 'ro',
    isa        => 'Str',
    traits     => [ 'Getopt' ],
    cmd_flag   => 'lims2-client-config'
);

sub _build_lims2_client {
    my $self = shift;

    my %args;

    if ( defined $self->lims2_client_conffile ) {
        $args{configfile} = $self->lims2_client_conffile;
    }
    else{
    	$args{configfile} = $ENV{LIMS2_REST_CLIENT_CONF};
    }

    return LIMS2::REST::Client->new_with_config( %args );
}

1;

__END__
