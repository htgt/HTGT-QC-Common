package HTGT::QC::DistributionLogic;

use Moose;
use namespace::autoclean;

use Path::Class;
use Config::Scoped;
use Parse::BooleanLogic;
use HTGT::QC::Exception;

with qw( MooseX::Log::Log4perl );

has conffile => (
    is       => 'ro',
    isa      => 'Path::Class::File',
    required => 1,
    default  => sub { file($ENV{HTGT_QC_DIST_LOGIC_CONF}) }
);

has config => (
    is         => 'ro',
    isa        => 'HashRef',
    lazy_build => 1
);

has profile_name => (
    is       => 'ro',
    isa      => 'Str',
    init_arg => 'profile',
    required => 1
);

has qc_data => (
    is       => 'ro',
    isa      => 'HashRef',
    traits   => [ 'Hash' ],
    handles  =>{
        qc_data_types => 'keys',
        has_qc_pass   => 'get',
    },
    required => 1
);

has parser => (
    is         => 'ro',
    isa        => 'Parse::BooleanLogic',
    lazy_build => 1
);

has loxp_pass => (
    is         => 'ro',
    isa        => 'Bool',
    lazy_build => 1
);

has five_arm_pass => (
    is         => 'ro',
    isa        => 'Bool',
    lazy_build => 1
);

has three_arm_pass => (
    is         => 'ro',
    isa        => 'Bool',
    lazy_build => 1
);

has distribute => (
    is         => 'ro',
    isa        => 'Bool',
    lazy_build => 1
);

has targeted_trap => (
    is         => 'ro',
    isa        => 'Bool',
    lazy_build => 1
);

my %HANDLERS_FOR = (
    'GF'    => sub {shift->passes_matching( qr/^primer_band_GF\d$/ ) >= 1 },
    'GR'    => sub {shift->passes_matching( qr/^primer_band_GR\d$/ ) >= 1 },
    'GF>=2' => sub {shift->passes_matching( qr/^primer_band_GF\d$/ ) >= 2 },
    'GR>=2' => sub {shift->passes_matching( qr/^primer_band_GR\d$/ ) >= 2 },
    'TR'    => sub {shift->passes_matching( qr/^primer_band_TR_PCR$/ ) >= 1 },
    'LF'    => sub {shift->passes_matching( qr/^primer_read_._LF$/ ) >= 1 },
    'LR'    => sub {shift->passes_matching( qr/^primer_read_._LR$/ ) >= 1 },
    'LRR'   => sub {shift->passes_matching( qr/^primer_read_._LRR$/ ) >= 1 },
    'R1R'   => sub {shift->passes_matching( qr/^primer_read_._R1R$/ ) >= 1 },
    'Art5'  => sub {shift->passes_matching( qr/^primer_read_._Art5$/ ) >= 1 },
    'A_R2R' => sub {shift->has_qc_pass( 'primer_read_A_R2R' )},
    'B_R2R' => sub {shift->has_qc_pass( 'primer_read_B_R2R' )},
    'Z_R2R' => sub {shift->has_qc_pass( 'primer_read_Z_R2R' )},
    'R_R2R' => sub {shift->has_qc_pass( 'primer_read_R_R2R' )},
    'C_R2R' => sub {shift->has_qc_pass( 'primer_read_C_R2R' )},
    'A_LFR' => sub {shift->has_qc_pass( 'primer_read_A_LFR' )},
    'B_LFR' => sub {shift->has_qc_pass( 'primer_read_B_LFR' )},
    'A_LR'  => sub {shift->has_qc_pass( 'primer_read_A_LR' )},
    'Z_LR'  => sub {shift->has_qc_pass( 'primer_read_Z_LR' )},
    'A_LRR' => sub {shift->has_qc_pass( 'primer_read_A_LRR' )},
    'Z_LRR' => sub {shift->has_qc_pass( 'primer_read_Z_LRR' )},
    'A_LF'  => sub {shift->has_qc_pass( 'primer_read_A_LF' )},
    'loxp_pass'      => sub {shift->loxp_pass},
    'loxp_fail'      => sub {shift->loxp_fail},
    'five_arm_pass'  => sub {shift->five_arm_pass},
    'three_arm_pass' => sub {shift->three_arm_pass}
);

sub BUILD{
    my ($self) = @_;

    $self->validate_config;
    $self->validate_qc_data;

    return;
}

sub _build_config {
    my ($self) = @_;

    $self->log->debug( 'Reading configuration from ' . $self->conffile );
    my $conf_parser = Config::Scoped->new(
        file     => $self->conffile->stringify,
        warnings => { permissions => 'off' }
    );

    my $config = $conf_parser->parse;
    $self->log->trace( sub { 'Config: ' . pp($config) } );

    return $config;
}

for my $method (qw(primer_band_TR_PCR
                   primer_band_GR1    primer_band_GR2    primer_band_GR3    primer_band_GR4
                   primer_band_GF1    primer_band_GF2    primer_band_GF3    primer_band_GF4
                   primer_read_A_LF   primer_read_B_LF   primer_read_C_LF
                   primer_read_A_LFR  primer_read_B_LFR
                   primer_read_A_LR   primer_read_C_LR   primer_read_Z_LR
                   primer_read_A_LRR  primer_read_B_LRR  primer_read_Z_LRR  primer_read_C_LRR
                   primer_read_A_R1R  primer_read_B_R1R  primer_read_R_R1R  primer_read_C_R1R
                   primer_read_A_R2R  primer_read_B_R2R  primer_read_Z_R2R  primer_read_R_R2R
                   primer_read_C_R2R
                   primer_read_A_Art5 primer_read_B_Art5 primer_read_Z_Art5 primer_read_R_Art5
                   primer_read_Z_LR
              ) ) {
    __PACKAGE__->meta->add_method(
        $method => sub {
            my ($self) = @_;
            return $self->qc_data->{$method};
        }
    );
}

for my $band (qw( GF GR )) {
    __PACKAGE__->meta->add_method(
        'at_least_one_primer_band_' . $band => sub {
            my ($self) = @_;

            return $self->count_passes( map { 'primer_band_' . $band . $_ } qw( 4 3 2 1 ) ) > 0;
        }
    );
}

for my $band (qw( GF GR )) {
    __PACKAGE__->meta->add_method(
        'at_least_two_primer_bands_' . $band => sub {
            my ($self) = @_;

            return $self->count_passes( map { 'primer_band_' . $band . $_ } qw( 4 3 2 1 ) ) > 1;
        }
    );
}

for my $primer (qw( LR LRR LF R1R R2R Art5 )) {
    __PACKAGE__->meta->add_method(
        'at_least_one_primer_read_' . $primer => sub {
            my ($self) = @_;

            return $self->count_passes( map { 'primer_read_' . $_ . '_' . $primer } qw( A B Z R C) ) > 0;
        }
    );
}

for my $qc_test (qw( loxp_pass five_arm_pass three_arm_pass distribute targeted_trap )) {
    __PACKAGE__->meta->add_method(
        '_build_' . $qc_test => sub {
            my ($self) = @_;

            my $condition = $self->config->{profile}{ $self->profile_name }{$qc_test};

            my $callback = sub {
                my $operand = $_[0]->{operand};
                my $code_ref = $self->handler_for_operand($operand);
                $code_ref->($self);
            };
            return $self->parser->solve( $self->parser->as_array($condition), $callback );
        }
    );
}

sub handler_for_operand{
    my ($self, $operand) = @_;

    HTGT::QC::Exception->throw("Invalid operand $operand in config profile")
          unless exists $HANDLERS_FOR{$operand};

    return $HANDLERS_FOR{$operand};
}

sub _build_parser {
    return Parse::BooleanLogic->new();
}

sub validate_config {
    my ($self) = @_;

    my %operands;
    for my $profile( keys %{$self->config->{'profile'}} ){
        for my $test( keys %{$self->config->{'profile'}{$profile}} ){
            my $condition_str = $self->config->{'profile'}{$profile}{$test};
            $self->parser->as_array(
                $condition_str,
                operand_cb => sub {
                    $operands{ $_[0] }++;
                }
            );
        }
    }

    for my $operand( keys %operands ){
        $self->handler_for_operand( $operand );
    }

    return;
}

sub validate_qc_data {
    my ($self) = @_;

    for my $primer_read_or_band( keys %{$self->qc_data} ){
        HTGT::QC::Exception->throw("Invalid primer read/band $primer_read_or_band in qc_data")
              unless $self->can( $primer_read_or_band );
    }

    return;
}

sub loxp_fail {
    my ($self) = @_;

    return !$self->loxp_pass;
}

sub passes_matching{
    my ( $self, $match ) = @_;

    return scalar grep { $self->has_qc_pass($_) } grep { m/$match/ } $self->qc_data_types;
}

sub count_passes {
    my ( $self, @tests ) = @_;

    return scalar grep { $self->$_ } @tests;
}

__PACKAGE__->meta->make_immutable;

1;

__END__
