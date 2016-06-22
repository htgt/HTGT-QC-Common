package HTGT::QC::Util::ListTraceProjects;

use Moose;
use HTGT::Utils::BadgerRepository;
use HTGT::QC::Action::FetchSeqReads::TraceArchive;
use IPC::System::Simple qw( capturex );
use namespace::autoclean;

#this is a re-written version of HTGT::QC::Action::ListTraceProjects::Badger
#so it can be easily imported (for HTGT/LIMS2 es cell qc runs) 

has show_all => (
    is         => 'ro',
    isa        => 'Bool',
    default    => 0
);

has badger => (
    is         => 'ro',
    isa        => 'HTGT::Utils::BadgerRepository',
    lazy_build => 1
);

sub _build_badger {
    HTGT::Utils::BadgerRepository->new;
}

sub get_trace_projects {
    my ( $self, $trace_project ) = @_;

    my %projects;

    for my $a ( $self->expand_leading_zeroes( $trace_project ) ) {
        for my $p ( @{ $self->badger->search( $a ) } ) {
            if ( $self->show_all or $self->project_has_reads( $p ) ) {
                $projects{$p}++;
            }
            else {
                #print "WARNING: Project $p has no sequencing reads\n";
            }
        }   
    }

    return [ sort keys %projects ];
}

sub project_has_reads {
    my ( $self, $project_name ) = @_;
                   
    # This is a bit of a hack, but we need to know whether or not this project has any reads attached
    my @reads = capturex( HTGT::QC::Action::FetchSeqReads::TraceArchive->fetch_seq_reads_cmd, $project_name, '--list-only' );

    return @reads > 0;
}
        
sub expand_leading_zeroes {
    my ( $self, $name ) = @_;

    if ( my ( $prefix, $numbers, $suffix ) = $name =~ qr/^(\D+)(\d+)(\D+)?$/ ) {
        $suffix = '' unless defined $suffix;
        $numbers =~ s/^0+//;
        return map { $prefix . $_ . $numbers . $suffix } '', qw( 0 00 000 );
    }
    else {
        return $name;
    }
}        

__PACKAGE__->meta->make_immutable;

1;

__END__
