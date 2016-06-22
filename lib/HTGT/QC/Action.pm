package HTGT::QC::Action;

use Moose;
use MooseX::Types::Path::Class;
use HTGT::QC::Config;
use HTGT::QC::Exception;
use Log::Log4perl ':levels';
use Path::Class;
use namespace::autoclean;

extends 'MooseX::App::Cmd::Command';
with 'MooseX::Log::Log4perl';

has conffile => (
    is       => 'ro',
    isa      => 'Path::Class::File',
    traits   => [ 'Getopt' ],
    coerce   => 1,
    cmd_flag => 'config'
);

has [ qw( trace debug verbose ) ] => (
    is      => 'ro',
    isa     => 'Bool',
    traits  => [ 'Getopt' ],
    default => 0
);

has log_layout => (
    is       => 'ro',
    isa      => 'Str',
    traits   => [ 'Getopt' ],
    cmd_flag => 'log-layout',
    default  => '%d %p %C %x %m%n'
);

has profile_name => (
    is       => 'ro',
    isa      => 'Str',
    traits   => [ 'Getopt' ],
    cmd_flag => 'profile',
);

has config => (
    is         => 'ro',
    isa        => 'HTGT::QC::Config',
    traits     => [ 'NoGetopt' ],
    lazy_build => 1
);

has profile => (
    is         => 'ro',
    isa        => 'HTGT::QC::Config::Profile',
    traits     => [ 'NoGetopt' ],
    lazy_build => 1
);

has '+logger' => (
    traits => [ 'NoGetopt' ]
);

has cli_mode => (
    is      => 'ro',
    isa     => 'Bool',
    traits  => [ 'NoGetopt' ],
    default => 1
);

#needed a lims 2 flag for KillAndNotify, could be useful elsewhere.
has is_lims2 => (
    is         => 'ro',
    isa        => 'Bool',
    traits     => [ 'Getopt' ],
    default    => 0,
    cmd_flag   => 'is-lims2',
);

has is_prescreen => (
    is       => 'ro',
    isa      => 'Bool',
    traits   => [ 'Getopt' ],
    default  => 0,
    cmd_flag => 'is-prescreen',
);

sub BUILD {
    my $self = shift;

    $self->init_log4perl();
}

sub init_log4perl {
    my ( $self, $logfile ) = @_;

    my $log_level = $self->trace   ? $TRACE
                  : $self->debug   ? $DEBUG
                  : $self->verbose ? $INFO
                  :                  $WARN;

    my %args = (
        level  => $log_level,
        layout => $self->log_layout
    );

    $args{file} = '>>'.$logfile if defined $logfile;
    
    Log::Log4perl->easy_init( \%args );
}

sub _build_config {
    my $self = shift;

    my %args;
    if ( $self->conffile ) {
        $args{conffile} = $self->conffile;
        $args{is_lims2} = $self->is_lims2;
        $args{is_prescreen} = $self->is_prescreen;
    }

    HTGT::QC::Config->new( \%args )->validate;
}

sub _build_profile {
    my $self = shift;

    unless ( defined $self->profile_name ) {        
        HTGT::QC::Exception->throw( "No profile name specified" );
    }

    $self->config->profile( $self->profile_name );
}

__PACKAGE__->meta->make_immutable;

1;

__END__
