package HTGT::QC::Util::CrisprAlleleDamage;

=head1 NAME

HTGT::QC::Util::CrisprAlleleDamage

=head1 DESCRIPTION

Identify damage caused by crispr pairs on the second allele.
Compare wildtype genomic sequence of area around crispr pair target site with the sequence
from primer reads that flank this target site.

=cut

use Moose;
use HTGT::QC::Util::CigarParser;
use DesignCreate::Util::Exonerate;
use HTGT::QC::Util::Alignment qw( alignment_match_on_target );
use Bio::SeqIO;
use Data::Dumper;
use MooseX::Types::Path::Class::MoreCoercions qw/AbsDir/;
use namespace::autoclean;

with qw( MooseX::Log::Log4perl );

has genomic_region => (
    is       => 'ro',
    isa      => 'Bio::Seq',
    required => 1,
);

has forward_primer_name => (
    is       => 'ro',
    isa      => 'Str',
    required => 1,
);

has reverse_primer_name => (
    is       => 'ro',
    isa      => 'Str',
    required => 1,
);

has forward_primer_read => (
    is        => 'ro',
    isa       => 'Maybe[Bio::Seq]',
    predicate => 'has_forward_primer_read',
);

has reverse_primer_read => (
    is        => 'ro',
    isa       => 'Maybe[Bio::Seq]',
    predicate => 'has_reverse_primer_read',
);

has dir => (
    is       => 'ro',
    isa      => AbsDir,
    required => 1,
    coerce   => 1,
);

has cigar_parser => (
    is         => 'ro',
    isa        => 'HTGT::QC::Util::CigarParser',
    lazy_build => 1,
);

sub _build_cigar_parser {
    my $self = shift;
    return HTGT::QC::Util::CigarParser->new(
        primers => [ $self->forward_primer_name, $self->reverse_primer_name ] );
}

sub BUILD {
    my $self = shift;

    if ( !$self->has_forward_primer_read && !$self->has_reverse_primer_read ) {
        die("Must specify at least a forward or reverse primer read");
    }

    return;
}

=head2 analyse

Run the analysis of the primer reads against the genomic region.

=cut
sub analyse {
    my ( $self ) = @_;

    my $cigars = $self->align_reads();
    $self->display_alignments( $cigars );

    return;
}

=head2 display_alignments

Using the cigar strings and the target sequence display the reads aligned against the
genomic target region.

=cut
sub display_alignments {
    my ( $self, $cigars ) = @_;

    #TODO what I really need here is the genomic coordinates of the crispr pair
    #     we can not hard code the cut offs like this
    my $left_crispr_loc  = 150;
    my $right_crispr_loc = 270;
    my ( $fquery, $fmatch, $rquery, $rmatch, $ftarget, $rtarget );
    my ( $fmatch_substr, $rmatch_substr );

    if ( exists $cigars->{forward}) {
        ( $fquery, $ftarget, $fmatch )
            = alignment_match_on_target( $self->forward_primer_read, $self->genomic_region, $cigars->{forward} );
        $fquery  = substr( $fquery,  $left_crispr_loc, $right_crispr_loc - $left_crispr_loc + 1 );
        $ftarget = substr( $ftarget, $left_crispr_loc, $right_crispr_loc - $left_crispr_loc + 1 );
        $fmatch  = substr( $fmatch,  $left_crispr_loc, $right_crispr_loc - $left_crispr_loc + 1 );
    }

    if ( exists $cigars->{reverse} ) {
        ( $rquery, $rtarget, $rmatch )
            = alignment_match_on_target( $self->reverse_primer_read, $self->genomic_region, $cigars->{reverse} );
        $rquery  = substr( $rquery,  $left_crispr_loc, $right_crispr_loc - $left_crispr_loc + 1 );
        $rtarget = substr( $rtarget, $left_crispr_loc, $right_crispr_loc - $left_crispr_loc + 1 );
        $rmatch  = substr( $rmatch,  $left_crispr_loc, $right_crispr_loc - $left_crispr_loc + 1 );
    }

    if ( $fquery && $rquery ) {
        print "$fquery\n$fmatch\n$ftarget\n-\n$rtarget\n$rmatch\n$rquery\n\n";
    }
    elsif ($fquery) {
        print "$fquery\n$fmatch\n$ftarget\n-\n\n";
    }
    elsif ($rquery) {
        print "-\n$rtarget\n$rmatch\n$rquery\n\n";
    }
}

=head2 align_reads

Align primer reads against genomic region where damage is expected, expect cigar strings as output.
We run exonerate in exhaustive mode, with a gapped model and only take the best result.

=cut
sub align_reads {
    my $self = shift;
    $self->log->debug( 'Align reads' );

    my ( $target_file, $query_file ) = $self->create_exonerate_files();

    my $exonerate = DesignCreate::Util::Exonerate->new(
        target_file   => $target_file,
        query_file    => $query_file,
        bestn         => 1,
        showcigar     => 'yes',
        showalignment => 'yes',
        model         => 'affine:local',
        exhaustive    => 'yes',
    );

    $exonerate->run_exonerate;
    # put exonerate output in a log file
    my $fh = $self->dir->file('exonerate_output')->openw;
    my $raw_output = $exonerate->raw_output;
    print $fh $raw_output;

    my @cigar_strings = grep{ /^cigar:/ } split("\n", $raw_output);

    my %cigars;
    for my $cigar ( @cigar_strings ) {
        my $result = $self->cigar_parser->parse_cigar($cigar);

        if ( $result->{query_primer} eq $self->forward_primer_name ) {
            $cigars{forward} = $result;
        }
        elsif ( $result->{query_primer} eq $self->reverse_primer_name ) {
            $cigars{reverse} = $result;
        }
        else {
            $self->log->error( "Unknown primer $result->{query_primer}, "
                    . "does not match foward: " . $self->forward_primer_name
                    . ", or reverse: " . $self->reverse_primer_name
                    . ' primer names.' );
        }
        #TODO check well names? $result->{query_well};
    }

    return \%cigars;
}

=head2 create_exonerate_files

Create the target and query fasta files that will be in the input to exonerate.

=cut
sub create_exonerate_files {
    my $self = shift;

    my $query_file    = $self->dir->file('exonerate_query.fasta')->absolute;
    my $query_fh      = $query_file->openw;
    my $query_seq_out = Bio::SeqIO->new( -fh => $query_fh, -format => 'fasta' );

    $query_seq_out->write_seq( $self->forward_primer_read ) if $self->forward_primer_read;
    $query_seq_out->write_seq( $self->reverse_primer_read ) if $self->reverse_primer_read;

    my $target_file = $self->dir->file('target_query.fasta')->absolute;
    my $target_fh         = $target_file->openw;
    my $target_seq_out    = Bio::SeqIO->new( -fh => $target_fh, -format => 'fasta' );

    $target_seq_out->write_seq( $self->genomic_region );

    $self->log->debug("Created exonerate query and target files");

    return ( $target_file, $query_file );
}

__PACKAGE__->meta->make_immutable;

1;

__END__
