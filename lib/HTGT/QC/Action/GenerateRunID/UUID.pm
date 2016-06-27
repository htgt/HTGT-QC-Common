package HTGT::QC::Action::GenerateRunID::UUID;

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
}

__PACKAGE__->meta->make_immutable;

1;

__END__
