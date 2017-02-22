package HTGT::QC::Util::MergeVariantsVCF;
## no critic(RequireUseStrict,RequireUseWarnings)
{
    $HTGT::QC::Util::MergeVariantsVCF::VERSION = '0.050';
}
## use critic


=head1 NAME

HTGT::QC::Util::MergeVariantsVCF

=head1 DESCRIPTION

Take a vcf file and attempt to produce a new vcf file with all
the variants merged into one.

This is hack that lets us run the resultant merged vcf file through VEP
which will then produce one mutant protein sequence ( instead of multiple sequences
for each variant ). The output from VEP when doing this is not optimal.

We should find another way to produce the reference and mutant protein sequences and
stop merging the variants.


=cut

use Moose;
use MooseX::Types::Path::Class::MoreCoercions qw/AbsDir AbsFile/;
use Path::Class;
use Bio::SeqIO;
use IPC::Run 'run';
use HTGT::QC::Constants qw(
    $SAMTOOLS_CMD
    %BWA_REF_GENOMES
);
use namespace::autoclean;

with qw( MooseX::Log::Log4perl );

has vcf_file => (
    is       => 'rw',
    isa      => AbsFile,
    coerce   => 1,
    required => 1,
);

has species => (
    is       => 'ro',
    isa      => 'Str',
    required => 1,
);

has dir => (
    is       => 'ro',
    isa      => AbsDir,
    required => 1,
    coerce   => 1,
);

has vcf_header => (
    is  => 'rw',
    isa => 'ArrayRef',
);

has variants => (
    is      => 'rw',
    isa     => 'ArrayRef',
    traits  => [ 'Array' ],
    default => sub{ [] },
    handles => {
        no_variants  => 'is_empty',
        num_variants => 'count',
        all_variants => 'elements',
    }
);

has variant_alt_seqs => (
    is      => 'rw',
    isa     => 'ArrayRef',
    default => sub{ [] },
);

has start => (
    is         => 'rw',
    isa        => 'Int',
    lazy_build => 1,
);

sub _build_start {
    return shift->variants->[0][1];
}

has end => (
    is         => 'rw',
    isa        => 'Int',
    lazy_build => 1,
);

sub _build_end {
    my $self = shift;
    my $last_variant = $self->variants->[-1];

    # position of last variant plus the length of the ref sequence
    return $last_variant->[1] + ( length( $last_variant->[3] ) -1 );
}

has chromosome => (
    is         => 'rw',
    isa        => 'Str',
    lazy_build => 1,
);

sub _build_chromosome {
    return shift->variants->[0][0];
}

has merged_vcf_file => (
    is  => 'rw',
    isa => 'Path::Class::File',
);

=head2 create_merged_vcf

Take the original vcf file and produce a merged vcf file is possible.

=cut
sub create_merged_vcf {
    my ( $self ) = @_;
    $self->log->info( 'Attempting to merge variants in vcf file: ' . $self->vcf_file->stringify );

    $self->parse_vcf_file;
    if ( $self->no_variants ) {
        $self->log->warn( 'No variants in vcf, nothing to merge' );
        return;
    }
    elsif ( $self->num_variants == 1 ) {
        $self->log->warn( 'Only one variant in vcf, nothing to do' );
        return;
    }

    return unless $self->process_variants;

    $self->create_merged_vcf_file;

    $self->log->info( 'Created merged VCF file: ' . $self->merged_vcf_file->stringify );
    return $self->merged_vcf_file;
}

=head2 parse_vcf_file

Parse the variants into a array of arrays.
Store the vcf header information.

=cut
sub parse_vcf_file {
    my ( $self ) = @_;
    $self->log->debug( 'Parsing VCF file' );

    my @lines = $self->vcf_file->slurp( chomp => 1 );
    $self->vcf_header( [ grep { /^#/ } @lines ] );
    $self->variants( [ map{ [ split/\t/ ] } grep { !/^#/ } @lines ] );

    return;
}

=head2 process_variants

Process the variants, this will eventually let us create
the new alt sequence for the merged variant.
Also does checks to see if we can actually merge the variants.

=cut
sub process_variants {
    my ( $self ) = @_;
    $self->log->debug( 'Processing variants in VCF file' );

    for my $var ( $self->all_variants ) {
        my $var_info = $var->[7];

        return if $self->cannot_merge_variant( $var_info );

        my $pos = $var->[1];
        my $alt_seq = $var->[4];
        my $ref_seq = $var->[3];
        # want variants in reverse order
        unshift @{ $self->variant_alt_seqs }, {
            pos     => $pos - $self->start, # relative to ref_seq
            var_seq => $alt_seq,
            ref_seq => $ref_seq,
        };
    }

    return 1;
}

=head2 cannot_merge_variant

Check to see if we can merge this variant.
If we have 2 reads and any of the variants are non concordant then we cannot merge.

=cut
sub cannot_merge_variant {
    my ( $self, $var_info ) = @_;

    # if we just have 1 read supporting the variant its always okay
    if ( $var_info =~ /DP=2/ ) {
        if ( $var_info =~ /^INDEL/ ) {
            if ( $var_info =~ /IDV=1/ ) {
                $self->log->warn( 'Non concordant INDEL, cannot merge' );
                return 1;
            }
        }
        else {
            #<ID=DP4,Number=4,Type=Integer,Description="Number of high-quality ref-forward , ref-reverse, alt-forward and alt-reverse bases">
            if ( $var_info =~ /DP4=(\d,\d,\d,\d);/ ) {
                my @num_reads = split( ',', $1 );
                if ( $num_reads[0] == 1 || $num_reads[1] == 1 ) {
                    $self->log->warn( 'Non concordant SNP, cannot merge' );
                    return 1;
                }
            }
            else {
                $self->log->error( "Cannot tell how many reads support variant: $var_info" );
                return 1;
            }
        }
    }

    return;
}

=head2 create_merged_vcf_file

Create the merged vcf file.

=cut
sub create_merged_vcf_file {
    my ( $self ) = @_;
    $self->log->debug( 'Creating new VCF file with merged variants' );

    my $ref_seq = $self->grab_genomic_seq;
    my $var_seq = $self->create_variant_seq( $ref_seq );

    $self->merged_vcf_file( $self->dir->file( 'merged_variants.vcf' ) );
    my $fh = $self->merged_vcf_file->openw;
    print $fh join( "\n", @{ $self->vcf_header } );

    my @merged_variant = (
        $self->chromosome,
        $self->start,
        '.', # ID
        $ref_seq,
        $var_seq,
        '.', # quality
        '.', # filter
        '.', # info
        '.', # format of genotype data
        '.', # genotype data
    );
    print $fh "\n" . join( "\t", @merged_variant );

    return;
}

=head2 grab_genomic_seq

Grab genomic sequence from specified coordinates.

=cut
sub grab_genomic_seq {
    my ( $self ) = @_;
    $self->log->debug( 'Grabbing reference sequence for merged variant' );

    my $target_string = $self->chromosome . ':' . $self->start . '-' . $self->end;
    my @samtools_faidx_cmd = (
        $SAMTOOLS_CMD,
        'faidx',                            # mpileup command
        $BWA_REF_GENOMES{ lc( $self->species ) }, # reference genome file, faidx-indexed
        $target_string
    );

    my $missing_seq_file = $self->dir->file('missing_sequence.fa')->absolute;
    run( \@samtools_faidx_cmd,
        '>',  $missing_seq_file->stringify,
    ) or die(
            "Failed to run samtools faidx command" );

    my $missing_seq = Bio::SeqIO->new( -fh => $missing_seq_file->openr, -format => 'fasta' );

    return $missing_seq->next_seq->seq;
}

=head2 create_variant_seq

Create variant sequence by transforming the reference sequence
using each variant, working 3' to 5'.

=cut
sub create_variant_seq {
    my ( $self, $ref_seq ) = @_;
    $self->log->debug( 'Creating alternate variant sequence for merged variant' );

    my $var_seq = $ref_seq;

    for my $alt ( @{ $self->variant_alt_seqs } ) {
        substr( $var_seq, $alt->{pos}, length($alt->{ref_seq}), $alt->{var_seq} );
    }

    return $var_seq;
}

__PACKAGE__->meta->make_immutable;

1;

__END__
