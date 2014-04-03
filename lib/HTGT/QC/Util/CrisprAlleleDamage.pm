package HTGT::QC::Util::CrisprAlleleDamage;

=head1 NAME

HTGT::QC::Util::CrisprAlleleDamage

=head1 DESCRIPTION


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

has well_name => (
    is       => 'ro',
    isa      => 'Str',
    required => 1,
);

has genomic_region => (
    is       => 'ro',
    isa      => 'Bio::Seq',
    required => 1,
);

has forward_primer_name => (
    is  => 'ro',
    isa => 'Str',
);

has reverse_primer_name => (
    is  => 'ro',
    isa => 'Str',
);

has forward_primer_read => (
    is  => 'ro',
    isa => 'Bio::Seq',
);

has reverse_primer_read => (
    is  => 'ro',
    isa => 'Bio::Seq',
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
    required   => 1,
);

#TODO work out well name from both primer read display names?
#     do i really need the well name?

sub _build_cigar_parser {
    my $self = shift;
    return HTGT::QC::Util::CigarParser->new(
        primers => [ $self->forward_primer_name, $self->reverse_primer_name ] );
}

sub BUILD {
    my $self = shift;

    # TODO - validation of primer reads
    # add tests for following:
    # need at least one primer read ( forward or reverse )
    # if we have a primer read we also need its name

    # check the well name for the primer reads is correct?
    #   - would require user to pass in well name
    # check the primer names are corrext?

    #my ( $well, $primer ) = $display_name =~ $parser->query_primer_rx;

}

=head2 analyse

=cut
sub analyse {
    my ( $self ) = @_;

    # grab genomic region
    # grab primer reads ( should be 2, one forward one reverse )

    # run exonerate against the genomic region and both primer reads

    # grab cigar strings from exonerate results
    # run cigar string parser against them
    # NOTE: can grab the primer name and well name from the cigar string if needed
    #       not sure I need them though

    # ....
    my $cigars = $self->align_reads();

    # gather forward and reverse primer read sequences, cigar strings and target sequence
    # run aligment analysis

    # ....
}

=head2 _analyse

rename

=cut
sub _analyse {
    my ( $self, $cigars ) = @_;
    
    my ( $forward_cigar, $reverse_cigar );
    if ( exists $cigars->{ $self->forward_primer_name } ) {
        $forward_cigar = $cigars->{ $self->forward_primer_name };
    }
    if ( exists $cigars->{ $self->reverse_primer_name } ) {
        $reverse_cigar = $cigars->{ $self->reverse_primer_name };
    }

    my $left_crispr_loc  = 150;
    my $right_crispr_loc = 270;
    my ( $fquery, $fmatch, $rquery, $rmatch, $ftarget, $rtarget );
    my ( $fmatch_substr, $rmatch_substr );
    if ( $self->forward_primer_read && $forward_cigar->{target_strand} ) {
        ( $fquery, $ftarget, $fmatch )
            = alignment_match_on_target( $forward_seq, $target_seq, $forward_cigar );
        $fquery  = substr( $fquery,  $left_crispr_loc, $right_crispr_loc - $left_crispr_loc + 1 );
        $ftarget = substr( $ftarget, $left_crispr_loc, $right_crispr_loc - $left_crispr_loc + 1 );
        $fmatch  = substr( $fmatch,  $left_crispr_loc, $right_crispr_loc - $left_crispr_loc + 1 );
    }
    if ( $self->reverse_primer_read && $reverse_cigar->{target_strand} ) {
        ( $rquery, $rtarget, $rmatch )
            = alignment_match_on_target( $reverse_seq, $target_seq, $reverse_cigar );
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

desc
    # exonerate --showcigar true --showalignment true --model affine:local --query ATP2B4_140114.fa --target atp2b4_exon.fa --exhaustive yes --bestn 1

=cut
sub align_reads {
    my $self = shift;

    my ( $target_file, $query_file ) = $self->create_exonerate_files();

    my $exonerate = DesignCreate::Util::Exonerate->new(
        target_file   => $target_file,
        query_file    => $query_file,
        bestn         => 1,
        showcigar     => 'yes',
        showalignment => 'yes',
        model         => 'affine:local',
    );

    $exonerate->run_exonerate;
    # put exonerate output in a log file
    my $exonerate_output = $self->dir->file('exonerate_output');
    my $fh = $exonerate_output->openw;
    my $raw_output = $exonerate->raw_output;
    print $fh $raw_output;

    my @cigar_strings = grep{ /^cigar:/ } split("\n", $raw_output);

    my %cigars;
    for my $cigar ( @cigar_strings ) {
        my $result = $self->cigar_parser->parse_cigar($cigar);
        $cigars{ $result->{query_primer} } = $result;
        #TODO check wells the same?
        #my $well   = $result->{query_well};
    }

    return \%cigars;
}

=head2 create_exonerate_files

desc

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
