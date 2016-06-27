package HTGT::QC::Action::ListFailedRuns::DaemonDir;

use Moose;
use HTGT::QC::Util::ListFailedRuns;
use namespace::autoclean;

extends qw( HTGT::QC::Action );

override command_names => sub {
    'list-failed-runs'
};

override abstract => sub{
    'list details of latest 20 failed QC runs'
};

has limit => (
    is      => 'ro',
    isa     => 'Int',
    traits  => [ 'Getopt' ],
    default => 20
);

sub execute {
    my ( $self ) = @_;

    my $lfr = HTGT::QC::Util::ListFailedRuns->new(
        {
            limit => $self->limit,
            config => $self->config
        }
    );

    my $failed_run_data = $lfr->get_failed_run_data;

    for my $failure( @{$failed_run_data} ){
        print join( "\t", ( $failure->{qc_run_id}, $failure->{created}, $failure->{profile},
                            $failure->{seq_projects}, $failure->{template_plate} ) ) . "\n";
    }

    return;
}

__PACKAGE__->meta->make_immutable;

1;

__END__
