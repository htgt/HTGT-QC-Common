package HTGT::QC::Action::GenerateRunID::UUID;
## no critic(RequireUseStrict,RequireUseWarnings)
{
    $HTGT::QC::Action::GenerateRunID::UUID::VERSION = '0.050';
}
## use critic


use Moose;
use Data::UUID;
use namespace::autoclean;

extends qw( HTGT::QC::Action );

override command_names => sub {
    'generate-run-id'
};

override abstract => sub {
    'generate UUID for a new QC run'
};

sub execute {
    my $self = shift;

    my $uuid = Data::UUID->new->create_str;

    if ( $self->cli_mode ) {
        print $uuid . "\n";
    }
    else {
        return $uuid;
    }
    return;
}

__PACKAGE__->meta->make_immutable;

1;

__END__
