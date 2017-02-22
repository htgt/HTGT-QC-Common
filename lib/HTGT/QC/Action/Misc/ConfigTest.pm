package HTGT::QC::Action::Misc::ConfigTest;
## no critic(RequireUseStrict,RequireUseWarnings)
{
    $HTGT::QC::Action::Misc::ConfigTest::VERSION = '0.050';
}
## use critic


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
    return;
}

__PACKAGE__->meta->make_immutable;

1;

__END__
