package HTGT::QC::Action::Misc::WriteEngSeqs;
## no critic(RequireUseStrict,RequireUseWarnings)
{
    $HTGT::QC::Action::Misc::WriteEngSeqs::VERSION = '0.050';
}
## use critic


use Moose;
use MooseX::ClassAttribute;
use MooseX::Types::Path::Class;
use EngSeqBuilder;
use YAML::Any;
use Fcntl; # O_ constants
use namespace::autoclean;

extends qw( HTGT::QC::Action );

override command_names => sub {
    'write-eng-seqs'
};

override abstract => sub {
    'create engineered sequence genbank files from qc template plate'
};

class_has formats => (
    isa        => 'HashRef',
    traits     => [ 'Hash' ],
    handles    => {
        formats    => 'keys',
        suffix_for => 'get'
    },
    default    => sub {
        +{
            genbank => '.gbk',
            fasta   => '.fasta'
        }
    }
);

has output_dir => (
    is         => 'ro',
    isa        => 'Path::Class::Dir',
    traits     => [ 'Getopt' ],
    cmd_flag   => 'output-dir',
    required   => 1,
    coerce     => 1,
    trigger    => \&_init_output_dir
);

has eng_seq_builder => (
    is         => 'ro',
    isa        => 'EngSeqBuilder',
    lazy_build => 1,
    handles    => [
        qw( conditional_vector_seq
            deletion_vector_seq
            insertion_vector_seq
            conditional_allele_seq
            deletion_allele_seq
            insertion_allele_seq
            targeted_trap_allele_seq
            crispr_vector_seq
      )
    ]
);

sub _init_output_dir {
    my ( $self, $dir ) = @_;

    $dir->mkpath();
    return;
}

sub _build_eng_seq_builder {
    my $self = shift;
    my $eng_seq_builder;
    if ( $ENV{ENG_SEQ_BUILDER_CONFIG} ) {
        $eng_seq_builder = EngSeqBuilder->new( configfile => $ENV{ENG_SEQ_BUILDER_CONFIG} );
    }
    else {
        $eng_seq_builder = EngSeqBuilder->new();
    }
    $self->log->debug("Created EngSeqBuilder using config file at ".$eng_seq_builder->configfile->stringify);
    return $eng_seq_builder;
}

sub execute {
    my ( $self, $opts, $args ) = @_;

    my $template_data = YAML::Any::LoadFile( $args->[0] );

    my $well_params = $template_data->{wells};

    my %seen_eng_seq_ids;
    for my $p ( values %{ $well_params } ) {
        my $eng_seq_id = $p->{eng_seq_id};
        next if exists $seen_eng_seq_ids{$eng_seq_id};
        $seen_eng_seq_ids{$eng_seq_id}++;

        my $method = $p->{eng_seq_method};
        my $bio_seq = $self->$method( %{ $p->{eng_seq_params} } );
        $bio_seq->display_id( $eng_seq_id );
        $self->write_seq( $bio_seq, $eng_seq_id );
    }
    return;
}

sub write_seq {
    my ( $self, $bio_seq ) = @_;

    for my $format ( $self->formats ) {
        my $suffix = $self->suffix_for( $format );
        my $file = $self->output_dir->file( $bio_seq->display_id . $suffix );
        my $fh = $file->open( O_WRONLY|O_CREAT|O_EXCL )
            or HTGT::QC::Exception->throw( "Open $file: $!" );
        my $seq_out = Bio::SeqIO->new( -fh => $fh, -format => $format );
        $seq_out->write_seq( $bio_seq );
    }

    return;
}

__PACKAGE__->meta->make_immutable;

1;

__END__
