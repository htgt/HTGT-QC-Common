package HTGT::QC::Action::FetchTemplateData::HTGTDB;

use Moose;
use HTGT::QC::Exception;
use HTGT::Utils::FetchHTGTEngSeqParams;
use HTGT::DBFactory;
use namespace::autoclean;

extends qw( HTGT::QC::Action::FetchTemplateData );

override command_names => sub {
    'fetch-template-data-htgt'
};

override abstract => sub {
    'fetch engineered sequence params for the specified HTGT template plate'
};

has vector_stage => (
    is         => 'ro',
    isa        => 'Str',
    traits     => [ 'Getopt' ],
    cmd_flag   => 'stage',
    required   => 1
);

for ( qw( flp cre dre ) ) {
    my $accessor = 'apply_'.$_;
    my $flag = 'apply-'.$_;
    has $accessor => (
        is       => 'ro',
        isa      => 'Bool',
        traits   => [ 'Getopt' ],
        cmd_flag => $flag,
        default  => sub { shift->profile->$accessor },
        lazy     => 1
    );
}

has recombinase_params => (
    is         => 'ro',
    isa        => 'ArrayRef[Str]',
    traits     => [ 'NoGetopt' ],
    lazy_build => 1
);

sub _build_recombinase_params {
    my $self = shift;

    my @recombinase;

    if ( $self->apply_flp ) {
        push @recombinase, 'flp';
    }
    if ( $self->apply_cre ) {
        push @recombinase, 'cre';
    }
    if ( $self->apply_dre ) {
        push @recombinase, 'dre';
    }
    
    return \@recombinase;    
}

sub get_eng_seq_params {
    my ( $self, $plate_name ) = @_;
    
    my $htgt = HTGT::DBFactory->connect( 'eucomm_vector' );

    my $plate = $htgt->resultset( 'Plate' )->find( { name => $plate_name }, { prefetch => 'wells' } )
        or HTGT::QC::Exception->throw( message =>  "Failed to retrieve plate '$plate_name'" );

    my %qc_template_params;

    $qc_template_params{name} = $plate->name;

    # XXX If the recombinase_params argument is not specified,
    # fetch_htgt_eng_seq_params() will look at plate_data/well_data on
    # the template plate.
    my $wells = fetch_htgt_eng_seq_params( $plate, $self->vector_stage, $self->recombinase_params );

    for my $well ( @{$wells} ) {
        $qc_template_params{wells}{ substr $well->{well_name}, -3 } = $well;
    }
    
    return \%qc_template_params;
}

__PACKAGE__->meta->make_immutable;

1;

__END__
