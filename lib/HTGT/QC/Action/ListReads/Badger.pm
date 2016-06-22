package HTGT::QC::Action::ListReads::Badger;

use Moose;
use HTGT::QC::Action::ListTraceProjects::Badger;
use HTGT::QC::Action::FetchSeqReads::TraceArchive;
use IPC::System::Simple qw( capturex );
use List::MoreUtils qw( uniq );
use namespace::autoclean;

extends qw( HTGT::QC::Action );

override command_names => sub {
    'list-sequencing-project-reads'
};

override abstract => sub {
    'list reads for the specified sequencing projects'
};

sub execute {
    my ( $self, $opts, $args ) = @_;

    my $list_projects = HTGT::QC::Action::ListTraceProjects::Badger->new(
        app      => $self->app,
        usage    => $self->usage,
        config   => $self->config,
        trace    => $self->trace,
        debug    => $self->debug,
        verbose  => $self->verbose,
        cli_mode => 0
    );

    my @reads;
    
    for my $sequencing_project ( uniq map { @{$_} } $list_projects->execute( undef, $args ) ) {
        $self->log->debug( "Listing reads for $sequencing_project" );
        push @reads, map { chomp; $_ } capturex( HTGT::QC::Action::FetchSeqReads::TraceArchive->fetch_seq_reads_cmd,
                                                 $sequencing_project,
                                                 '--list-only' );
    }        

    if ( $self->cli_mode ) {
        print "$_\n" for @reads;
    }
    else {
        return \@reads;
    }
}

__PACKAGE__->meta->make_immutable;

1;

__END__
