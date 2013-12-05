package HTGT::QC::Config;
# ABSTRACT: Common QC Code

use Moose;
use MooseX::Types::Path::Class;
use namespace::autoclean;

use Config::Scoped;
use Path::Class;
use Data::Dump 'pp';
use Try::Tiny;
use List::MoreUtils qw( any uniq );
use HTGT::QC::Config::Profile;
use HTGT::QC::Exception::InvalidConfiguration;

with 'MooseX::Log::Log4perl';

has conffile => (
    is       => 'ro',
    isa      => 'Path::Class::File',
    required => 1,
    coerce   => 1,
    default  => sub { file( $ENV{HTGT_QC_CONF} ) }
);

has is_lims2 => (
    is         => 'rw',
    isa        => 'Bool',
    default    => 0,
);

has is_prescreen => (
    is         => 'rw',
    isa        => 'Bool',
    default    => 0,
);

has _config => (
    is         => 'ro',
    isa        => 'HashRef',
    lazy_build => 1
);

sub _build__config {
    my $self = shift;

    $self->log->debug( 'Reading configuration from ' . $self->conffile );

    die "Specified config file '" . $self->conffile . "' doesn't exist"
        unless ( -e $self->conffile );

    my $parser = Config::Scoped->new(
        file     => $self->conffile->stringify,
        warnings => { permissions => 'off' }
    );

    my $config = $parser->parse;
    $self->log->trace( sub { 'Config: ' . pp( $config ) } );

    return $config;
}

sub software_version {
    return $HTGT::QC::Config::VERSION || '1.0.0_01';
}

sub basedir {
	my $self = shift;
	if ( $self->is_lims2 ) {
		return dir( $self->_config->{GLOBAL}->{lims2_basedir});
	}
    elsif ( $self->is_prescreen ) {
        return dir( $self->_config->{GLOBAL}->{prescreen_basedir} );
    }

    return dir( $self->_config->{GLOBAL}->{basedir} );
}

sub runner_basedir {
    return dir( shift->_config->{RUNNER}->{basedir} );
}

sub runner_max_parallel {
    return shift->_config->{RUNNER}->{max_parallel};
}

sub runner_poll_interval {
    return shift->_config->{RUNNER}->{poll_interval};
}

sub profiles {
    my $self = shift;

    return keys %{ $self->_config->{profile} || {} };
}

sub profile {
    my ( $self, $profile_name ) = @_;

    unless ( exists $self->_config->{profile}->{$profile_name} ) {
        HTGT::QC::Exception->throw( "Profile '$profile_name' not configured" );
    }

    return HTGT::QC::Config::Profile->new(
        profile_name => $profile_name,
        alignment_regions => $self->_config->{alignment_regions},
        %{ $self->_config->{profile}->{$profile_name} }
    );
}

sub validate {
    my $self = shift;

    my @errors;

    for my $required ( qw( basedir runner_basedir ) ) {
        push @errors, "Required parameter $required not defined"
            unless defined $self->$required;
    }

    push @errors, $self->_validate_alignment_regions();
    push @errors, $self->_validate_profiles();

    if ( @errors ) {
        HTGT::QC::Exception::InvalidConfiguration->throw(
            conffile => $self->conffile,
            errors   => \@errors
        );
    }

    return $self;
}

sub _validate_alignment_regions {
    my $self = shift;

    my $regions = $self->_config->{alignment_regions};

    unless ( $regions and scalar keys %{$regions} > 0 ) {
        return "No alignment_regions configured";
    }

    my @errors;

    while ( my ( $name, $region ) = each %{$regions} ) {
        for my $required ( qw( expected_strand start end genomic ) ) {
            unless ( defined $region->{$required} ) {
                push @errors, "Alignment region $name missing required parameter $required";
            }
        }
        unless ( any { defined $region->{$_} } qw( min_match_length min_match_pct ensure_no_indel ) ) {
            push @errors, "Alignment region $name missing pass condition";
        }
    }

    return @errors;
}

sub _validate_profiles {
    my $self = shift;

    my @profiles = $self->profiles
        or return "No profiles configured";

    my @errors;

    for my $profile_name ( @profiles ) {
        try {
            my $profile = $self->profile( $profile_name );
        }
        catch {
            s/at constructor .*//gsm;
            s/\n.*//gsm;
            push @errors, "Invalid profile $profile_name: $_";
        };
    }

    return @errors;
}

sub all_primers {
    my $self = shift;

    my %profiles = %{ $self->_config->{profile} };

    return [ sort { length($b) <=> length($a) } uniq map { keys %{ $profiles{$_}{primers} }  } keys %profiles ];
}

__PACKAGE__->meta->make_immutable;

1;

__END__
