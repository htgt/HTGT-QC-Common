package HTGT::QC::Action::AlignReads::Exonerate;

use Moose;
use HTGT::QC::Util::RunExonerate qw( run_exonerate );
use HTGT::QC::Exception;
use File::Find::Rule;
use namespace::autoclean;

extends qw( HTGT::QC::Action::AlignReads );

has model => (
    is       => 'ro',
    isa      => 'Str',
    traits   => [ 'Getopt' ],
    default  => 'affine:local'
);

has output_dir => (
    is       => 'ro',
    isa      => 'Path::Class::Dir',
    traits   => [ 'Getopt' ],
    cmd_flag => 'output-dir',
    coerce   => 1,
    required => 1
);

override command_names => sub {
    'align-reads-exonerate'
};

override abstract => sub {
    'align reads to engineered sequences using exonerate'
};

sub execute {
    my ( $self, $opts, $args ) = @_;

    my @eng_seqs;
    
    for my $a ( @{$args} ) {
        if ( -d $a ) {
            push @eng_seqs, File::Find::Rule->file()->name( '*.fasta' )->in( $a );
        }
        #underscore is a special filehandle that caches whatever file information was last fetched.
        elsif ( -f _ ) {
            push @eng_seqs, $a;
        }
        else {
            HTGT::QC::Exception->throw( "Not a file or directory: $a" );
        }
    }
    
    HTGT::QC::Exception->throw( "At least one engineered sequence must be given" )
            unless @eng_seqs > 0;
    
    $self->output_dir->mkpath;
    
    run_exonerate( $self->reads_file, \@eng_seqs, $self->output_dir, $self->model );
}

1;

__END__

