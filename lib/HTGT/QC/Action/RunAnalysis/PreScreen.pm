package HTGT::QC::Action::RunAnalysis::PreScreen;

use Moose;
use MooseX::Types::Path::Class;
use HTGT::QC::Util::Analysis;
use Path::Class;
use namespace::autoclean;
use Bio::EnsEMBL::Registry;

use HTGT::QC::Util::CigarParser;

extends qw( HTGT::QC::Action::RunAnalysis );

has alignments_file => (
    is       => 'ro',
    isa      => 'Path::Class::File',
    traits   => [ 'Getopt' ],
    cmd_flag => 'alignments',
    coerce   => 1,
    required => 1
);

has alignments => (
    is         => 'ro',
    isa        => 'HashRef',
    traits     => [ 'NoGetopt' ],
    lazy_build => 1
);

has output_file => (
    is       => 'ro',
    isa      => 'Path::Class::File',
    traits   => [ 'Getopt' ],
    cmd_flag => 'output-file',
    coerce   => 1,
    required => 1
);

sub _build_alignments {
    my $self = shift;

    my $registry = 'Bio::EnsEMBL::Registry';

    $registry->load_registry_from_db(
        -host     => 'ensembldb.ensembl.org',
        -user     => 'anonymous',
        -NO_CACHE => 1 #we need this otherwise duplicate slices return no genes.
    );

    #this won't work cause we need the registry. isn't there a mixin class for this?
    my $slice_adaptor = $registry->get_adaptor( 'Mus musculus', 'Core', 'Slice' );

    #create iterator for alignments
    my $it = HTGT::QC::Util::CigarParser->new(
        strict_mode => 0
    )->file_iterator( $self->alignments_file );

    my %alignments; 

    while ( my $cigar = $it->next ) {
        my $query_id = delete $cigar->{ query_id };
        $self->log->debug( 'Processing ' . $query_id );

        #extract the chromosome number (or letter) from the target_name (this comes from the genome.fa file)
        if ( $cigar->{ target_id } =~ /chromosome:GRCm\d+:(\w+):/ ) {
            $cigar->{ chromosome } = $1;
        }
        else {
            #sometimes the match is in a scaffold instead of a chromosome,
            #if that is the case we just ignore the match (it shouldnt happen v often)
            next;
        }

        #delete the fields we don't want with a hash slice as they add clutter to the output
        delete @{ $cigar }{ qw(op_str operations raw) };
        
        #extract the plate & well 
        ( $cigar->{ plate }, $cigar->{ well } ) = $cigar->{ query_well } =~ /^(.+)_\d{1,2}(\w{3})/;
        $cigar->{ length } = $cigar->{ query_end } - $cigar->{ query_start };

        my $slice = $slice_adaptor->fetch_by_region( 
                                        'chromosome', 
                                        $cigar->{ chromosome }, 
                                        $cigar->{ target_start }, 
                                        $cigar->{ target_end }
                                    );

        #get the external gene name. note: ensembl name could be different to ours
        $cigar->{ genes } = $self->get_genes( $slice );

        #finally add the whole sequence
        $cigar->{ sequence } = $self->seq_reads->{ $query_id }->seq;
        $cigar->{ read_length } = $self->seq_reads->{ $query_id }->length;

        #we might get more than one alignment, so store them all

        #use the query_id as the id for this whole cigar
        
        push @{ $alignments{$query_id} }, $cigar;
    }

    return \%alignments;
};

override command_names => sub {
    'run-pre-screen-analysis'
};

override abstract => sub {
    'analyse pre screen alignments and output to a yaml file'
};

sub execute {
    my ( $self, $opts, $args ) = @_;

    my $output_dir = $self->output_file->parent;
    $output_dir->mkpath unless -e $output_dir; 

    YAML::Any::DumpFile( $self->output_file, $self->alignments );
}

#
# display multiple if we get multiple.
# allow user to view the specific sequence
#

sub get_genes {
    my ( $self, $slice ) = @_;

    my $genes = $slice->get_all_Genes();

    #make sure we got at least one gene
    unless ( scalar @{ $genes } ) {
        $self->log->warn( "No genes found in slice (".$slice->start()." - ".$slice->end().")" );
        return [ "None found" ];
    }

    #return all genes we get, but generally we only expect 1
    return [ map { $_->external_name() } @{ $genes } ]; 
}

__PACKAGE__->meta->make_immutable;

1;

__END__
