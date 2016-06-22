package HTGT::QC::Action::ListTraceProjects::Badger;

use Moose;
use HTGT::Utils::BadgerRepository;
use HTGT::QC::Util::ListTraceProjects;
use HTGT::QC::Action::FetchSeqReads::TraceArchive;
use IPC::System::Simple qw( capturex );
use namespace::autoclean;

extends qw( HTGT::QC::Action );

override command_names => sub {
    'list-trace-projects'
};

override abstract => sub {
    'list matching sequencing projects in the trace archive'
};

has show_all => (
    is         => 'ro',
    isa        => 'Bool',
    traits     => [ 'Getopt' ],
    cmd_flag   => 'show-all',
    default    => 0
);

has badger => (
    is         => 'ro',
    isa        => 'HTGT::Utils::BadgerRepository',
    traits     => [ 'NoGetopt' ],
    lazy_build => 1
);

sub _build_badger {
    HTGT::Utils::BadgerRepository->new;
}

sub execute {
    my ( $self, $opts, $args ) = @_;

    #the functionality of this module has moved to HTGT::QC::Util::ListTraceProjects

    my $trace_projects = HTGT::QC::Util::ListTraceProjects->new();

    for my $epd_plate ( @{ $args } ) {
       my $projects = $trace_projects->get_trace_projects( $epd_plate, $self->show_all ); 
       print "$_\n" for @{ $projects };
    }     
}   

__PACKAGE__->meta->make_immutable;

1;

__END__
