package HTGT::QC::Util::CrisprAlleleDamage;
## no critic(RequireUseStrict,RequireUseWarnings)
{
    $HTGT::QC::Util::CrisprAlleleDamage::VERSION = '0.028';
}
## use critic


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
use List::Util qw( min );
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
Calculate the largest concordant indel shown by the reads.

=cut
sub analyse {
    my ( $self ) = @_;

    my $cigars = $self->align_reads();
    my $alignment_data = $self->analyse_alignments( $cigars );

    my $forward_aln = $alignment_data->{forward};
    my $reverse_aln = $alignment_data->{reverse};

    if ( !$forward_aln || !$reverse_aln ) {
        return $alignment_data;
    }

    my $deletions = $self->concordant_deletions(
        $forward_aln->{full_match_string},
        $reverse_aln->{full_match_string},
    );

    my $insertions;
    if (   %{ $forward_aln->{insertion_details} }
        && %{ $reverse_aln->{insertion_details} } )
    {
        $insertions = $self->concordant_insertions(
            $forward_aln->{full_match_string},
            $reverse_aln->{full_match_string},
            $forward_aln->{insertion_details},
            $reverse_aln->{insertion_details},
        );
    }

    # if we have both concordant insertions and deletions pick the longest one
    if ( $deletions && $insertions ) {
        if ( $deletions->{length} >= $insertions->{length} ) {
            $alignment_data->{concordant_indel} = $deletions;
        }
        else {
            $alignment_data->{concordant_indel} = $insertions;
        }
    }
    elsif ( $deletions ) {
        $alignment_data->{concordant_indel} = $deletions;
    }
    elsif ( $insertions ) {
        $alignment_data->{concordant_indel} = $insertions;
    }

    return $alignment_data;
}

=head2 analyse_alignments

Using the cigar strings and the target sequence analyse the reads aligned against the
genomic target region.

=cut
sub analyse_alignments {
    my ( $self, $cigars ) = @_;

    my %data;
    if ( exists $cigars->{forward}) {
        $data{forward}
            = alignment_match_on_target( $self->forward_primer_read, $self->genomic_region, $cigars->{forward} );
    }

    if ( exists $cigars->{reverse} ) {
        $data{reverse}
            = alignment_match_on_target( $self->reverse_primer_read, $self->genomic_region, $cigars->{reverse} );
    }

    return \%data;
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

    my $query_file    = $self->dir->file('primer_reads.fasta')->absolute;
    my $query_fh      = $query_file->openw;
    my $query_seq_out = Bio::SeqIO->new( -fh => $query_fh, -format => 'fasta' );

    $query_seq_out->write_seq( $self->forward_primer_read ) if $self->forward_primer_read;
    $query_seq_out->write_seq( $self->reverse_primer_read ) if $self->reverse_primer_read;

    my $target_file = $self->dir->file('genomic_region.fasta')->absolute;
    my $target_fh         = $target_file->openw;
    my $target_seq_out    = Bio::SeqIO->new( -fh => $target_fh, -format => 'fasta' );

    $target_seq_out->write_seq( $self->genomic_region );

    $self->log->debug("Created exonerate query and target files");

    return ( $target_file, $query_file );
}

=head2 concordant_deletions

Find the largest deletion that is present in both the forward and reverse
primer reads.

=cut
sub concordant_deletions {
    my ( $self, $forward_cigar, $reverse_cigar ) = @_;
    return if !$forward_cigar || !$reverse_cigar;

    my $string_length = min( length( $forward_cigar ), length( $reverse_cigar ) );

    my @f = split( //, $forward_cigar );
    my @r = split( //, $reverse_cigar );

    my $current_max_length = 0;
    my @concordant_positions;

    my $d_run = 0;
    my $d_run_pos;
    my $d_run_len;
    for ( my $i = 0; $i < $string_length; $i++ ) {
        my $f_char = $f[$i];
        my $r_char = $r[$i];

        if ( $f_char eq 'D' && $r_char eq 'D' ) {
            if ( $d_run ) {
                $d_run_len++;
            }
            else {
                $d_run = 1;
                $d_run_pos = $i;
                $d_run_len = 1;
            }
        }
        else {
            if ( $d_run ) {
                if ( $d_run_len > $current_max_length ) {
                    $current_max_length = $d_run_len;
                    @concordant_positions = $d_run_pos;
                }
                elsif ( $d_run_len == $current_max_length ) {
                    push @concordant_positions, $d_run_pos;
                }
                $d_run = 0;
                $d_run_pos = undef;
                $d_run_len = undef;
            }
        }
    }

    my $concordant_deletion;
    if ( $current_max_length ) {
        $concordant_deletion = {
            length    => $current_max_length,
            positions => \@concordant_positions,
        };
    }

    return $concordant_deletion;
}

=head2 concordant_insertions

Find the largest insertion that is present in both the forward and reverse
primer reads.

=cut
sub concordant_insertions {
    my ( $self, $forward_cigar, $reverse_cigar, $forward_insertions, $reverse_insertions ) = @_;

    my $forward_ins_positions = insertion_data( $forward_cigar );
    my $reverse_ins_positions = insertion_data( $reverse_cigar );

    my $current_max_length = 0;
    my $current_max_seq = '';
    my @concordant_positions;

    for my $forward_pos ( keys %{ $forward_ins_positions } ) {
        next unless exists $reverse_ins_positions->{$forward_pos};

        # insertion on same place in both cigars, now check if sequence the same
        my $forward_ins_seq = $forward_insertions->{$forward_pos};
        my $reverse_ins_seq = $reverse_insertions->{$forward_pos};

        if ( $reverse_ins_seq && $forward_ins_seq && $reverse_ins_seq eq $forward_ins_seq ) {
            my $ins_length = length( $forward_ins_seq );
            if ( $ins_length > $current_max_length ) {
                $current_max_length = $ins_length;
                $current_max_seq = $forward_ins_seq;
                @concordant_positions = ( $forward_pos );
            }
            elsif ( $ins_length == $current_max_length ) {
                push @concordant_positions, $forward_pos;
            }
        }
    }

    my $concordant_insertion;
    if ( $current_max_length ) {
        $concordant_insertion = {
            length    => $current_max_length,
            positions => \@concordant_positions,
            seq       => $current_max_seq,
        };
    }

    return $concordant_insertion;
}

=head2 insertion_data

Find the position of all the Q characters on the cigar string.
The Q represents a insertion of one or more bases.

=cut
sub insertion_data {
    my $string = shift;

    my %data;
    while ($string =~ /Q/g) {
        # we work with 1 based coordinates
        my $start = $-[0] + 1;
        $data{$start} = undef;
    }

    return \%data;
}

__PACKAGE__->meta->make_immutable;

1;

__END__
