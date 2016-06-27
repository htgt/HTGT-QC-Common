package HTGT::QC::Action::Misc::RevcomBackbones;

use Moose;
use Path::Class;
use Bio::SeqUtils;
use Bio::SeqIO;
use List::Util qw( first );
use namespace::autoclean;

extends qw( HTGT::QC::Action );

override command_names => sub {
    'revcom-backbones'
};

override abstract => sub {
    'emit a new GenBank (and FASTA) file with the backbone reverse-complemented'
};

my %SUFFIX_FOR = (
    genbank => '.gbk',
    fasta   => '.fasta'
);

sub execute {
    my ( $self, $opts, $args ) = @_;

    for my $file ( map { file( $_ ) } @{ $args } ) {
        $self->revcom_backbone( $file );
    }
}

sub revcom_backbone {
    my ( $self, $file ) = @_;

    $self->log->info( "Processing $file" );
    
    ( my $basename = $file->basename ) =~ s/\.[^.]+//;

    my $seq = Bio::SeqIO->new( -file => "$file", -format => 'genbank' )->next_seq;

    my $bb_feature = first { $self->is_synthetic_backbone( $_ ) } $seq->get_SeqFeatures
        or die "Failed to find synthetic backbone in $file\n";

    my $new_seq = Bio::Seq->new(
        -alphabet    => 'dna',
        -seq         => '',
        -display_id  => $seq->display_id . '#r',
        -is_circular => $seq->is_circular
    );    

    # Sequence before backbone (if any)
    if ( $bb_feature->start > 1 ) {
        Bio::SeqUtils->cat(
            $new_seq,
            Bio::SeqUtils->trunc_with_features( $seq, 1, $bb_feature->start - 1 )
        );
    }

    # Reverse complement of the backbone itself
    Bio::SeqUtils->cat(
        $new_seq,
        Bio::SeqUtils->revcom_with_features(
            Bio::SeqUtils->trunc_with_features( $seq, $bb_feature->start, $bb_feature->end )
        )
    );                        

    # Sequence after the backbone (if any)
    if ( $bb_feature->end < $seq->length ) {
        Bio::SeqUtils->cat(
            $new_seq,
            Bio::SeqUtils->trunc_with_features( $seq, $bb_feature->end + 1, $seq->length )
        );
    }

    while ( my ( $format, $suffix ) = each %SUFFIX_FOR ) {
        my $new_file = $file->dir->file( $new_seq->display_id . $suffix );
        my $seq_io   = Bio::SeqIO->new( -fh => $new_file->openw, -format => $format );
        $seq_io->write_seq( $new_seq );
    }
}

sub is_synthetic_backbone {
    my ( $self, $feature ) = @_;

    if ( $feature->primary_tag eq 'misc_feature' ) {
        for my $value ( $feature->get_tag_values( 'note' ) ) {
            if ( $value eq 'Synthetic Backbone' ) {
                return 1;
            }
        }
    }

    return;
}

__PACKAGE__->meta->make_immutable;

1;

__END__

