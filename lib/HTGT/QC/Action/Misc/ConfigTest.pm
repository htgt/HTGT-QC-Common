package HTGT::QC::Action::Misc::ConfigTest;

use Moose;
use namespace::autoclean;

extends qw( HTGT::QC::Action );

override command_names => sub {
    'config-test'
};

override abstract => sub {
    'check the syntax of the configuration file'
};

sub execute {
    my ( $self, $opt, $args ) = @_;

    $self->config and print "Configuration OK\n";
}

__PACKAGE__->meta->make_immutable;

1;

__END__
