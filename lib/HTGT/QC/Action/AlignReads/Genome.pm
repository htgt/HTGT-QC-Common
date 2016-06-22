package HTGT::QC::Action::AlignReads::Genome;

use Moose;
use HTGT::QC::Exception;
use Path::Class;
use HTGT::QC::Util::RunCmd qw( run_cmd );

extends qw( HTGT::QC::Action::AlignReads );

has genome => (
    is       => 'ro',
    isa      => 'Path::Class::File',
    traits   => [ 'Getopt' ],
    cmd_flag => 'genome',
    coerce   => 1,
    default  => sub { file( '/data/blastdb/Ensembl/Mouse/GRCm38/unmasked/toplevel.fa' ) }
);

has show_alignments => (
    is       => 'ro',
    isa      => 'Bool',
    traits   => [ 'Getopt' ],
    cmd_flag => 'show-alignments',
    default  => 0
);

override command_names => sub {
    'align-reads-genome'
};

override abstract => sub {
    'align reads to a genome using exonerate'
};

sub bool_to_str {
    return ( shift ) ? "yes" : "no";
}

sub execute {
    my ( $self, $opts, $args ) = @_;

    #prevent exonerate from killing everything if the reads file doesn't exist.
    unless ( -e $self->reads_file ) {
        $self->log->debug( $self->reads_file . " doesn't exist, skipping." );
        return;
    }

    #exonerate needs yes/no not 1/0
    my $bool_to_str = sub {  };

    #exonerate command to align the users reads to the mouse genome.
    #output goes to stdout as i'm expecting this to be run on the farm
    my @cmd = (
        'exonerate',
        '--bestn', '2',
        '--score', '145', #minimum score to stop really low quality alignments
        '--showcigar', 'yes', #we're only interested in the cigar lines
        '--showvulgar', 'no', 
        '--showalignment', bool_to_str( $self->show_alignments ), 
        $self->reads_file, 
        $self->genome
    );

    print run_cmd( @cmd ), "\n";
}


1;

__END__
