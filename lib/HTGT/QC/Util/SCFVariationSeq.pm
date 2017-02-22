package HTGT::QC::Util::SCFVariationSeq;
## no critic(RequireUseStrict,RequireUseWarnings)
{
    $HTGT::QC::Util::SCFVariationSeq::VERSION = '0.050';
}
## use critic


=head1 NAME

HTGT::QC::Util::SCFVariationSeq

=head1 DESCRIPTION

Takes as input a SCF file with a heterozygous read and attempts to output
the variant / non-wildtype sequence from the trace.

=cut

use Moose;
use Bio::SeqIO;
use MooseX::Types::Path::Class::MoreCoercions qw/AbsFile AbsDir/;
use IPC::Run 'run';
use HTGT::QC::Constants qw(
    $SAMTOOLS_CMD
    %BWA_REF_GENOMES
);
use namespace::autoclean;

with qw( MooseX::Log::Log4perl );

# setup env variables needed to run the trace_recalling script
## no critic (Variables::RequireLocalizedPunctuationVars)
$ENV{PHRED_PARAMETER_FILE} = '/software/badger/etc/phredpar.dat';
$ENV{PERL5LIB} = '/opt/t87/global/software/trace_recalling-0.5-2/lib/perl5/vendor_perl/5.8.5:' . $ENV{PERL5LIB};
$ENV{PATH} = '/software/badger/bin:' . $ENV{PATH};
$ENV{PATH} = '/opt/t87/global/software/trace_recalling-0.5-2/bin:' . $ENV{PATH};
## use critic

has species => (
    is       => 'ro',
    isa      => 'Str',
    required => 1,
);

has [ 'target_start', 'target_end', 'target_strand' ] => (
    is       => 'ro',
    isa      => 'Int',
    required => 1,
);

has target_chr => (
    is       => 'ro',
    isa      => 'Str',
    required => 1,
);

has scf_file => (
    is       => 'ro',
    isa      => AbsFile,
    required => 1,
    coerce   => 1,
);

# fasta file
has ref_seq_file => (
    is        => 'rw',
    isa       => AbsFile,
    predicate => 'have_ref_seq_file',
);

has variant_seq_file => (
    is  => 'rw',
    isa => AbsFile,
);

has base_dir => (
    is       => 'ro',
    isa      => AbsDir,
    required => 1,
    coerce   => 1,
);

has work_dir => (
    is         => 'ro',
    isa        => AbsDir,
    lazy_build => 1,
);

sub _build_work_dir {
    my $self = shift;

    my $work_dir = $self->base_dir->subdir('scf_to_seq');
    $work_dir->mkpath;

    return $work_dir;
}

=head2 get_seq_from_scf

Extract the variant sequence from the SCF file.

=cut
sub get_seq_from_scf {
    my ( $self ) = @_;
    $self->log->info('Extracting variant sequence from heterozygous SCF file');

    $self->scf_file->copy_to( $self->work_dir );
    $self->create_ref_seq_file unless $self->have_ref_seq_file;
    $self->run_trace_recalling;
    $self->get_variant_seq_file;

    return $self->variant_seq_file;
}

=head2 run_trace_recalling

Run the main trace_recalling.pl script that extracts the variant sequence.

=cut
sub run_trace_recalling {
    my ( $self ) = @_;

    my $local_scf_file = $self->work_dir->file( $self->scf_file->basename );
    my @trace_recalling_cmd = (
        'trace_recalling.pl',
        '--mode=single,0.1',
        $local_scf_file->stringify,
        $self->ref_seq_file->stringify,
    );

    $self->log->debug( "trace_recalling command: " . join( ' ', @trace_recalling_cmd ) );
    my $log_file = $self->work_dir->file( 'trace_recalling.log' )->absolute;
    run( \@trace_recalling_cmd,
        '&>', $log_file->stringify
    ) or die(
            "Failed to run trace_recalling command, see log file: $log_file" );

    return;
}

=head2 get_variant_seq_file

Grab the variant sequence file from the directory that is created by
the trace_recalling.pl script.
Also cleanup the output to remove X characters, spaces and uppercase the sequence.

=cut
sub get_variant_seq_file {
    my ( $self ) = @_;

    # find scf work dir
    my $trace_recalling_dir = $self->work_dir->subdir( $self->scf_file->basename . '_dir' );
    die( "Can not find trace recalling dir: $trace_recalling_dir" )
        unless $self->work_dir->contains( $trace_recalling_dir );

    #find variant sequence file
    my $recall_file = $trace_recalling_dir->file( $self->scf_file->basename . '.recall' );
    die( "Can not find variant seq file $recall_file" )
        unless $trace_recalling_dir->contains( $recall_file );

    #cleanup seq file and write to new location
    my $variant_seqio = Bio::SeqIO->new( -fh => $recall_file->openr, -format => 'fasta' );
    my $bio_seq = $variant_seqio->next_seq;
    my $seq = $bio_seq->seq;
    $seq =~ s/X+//g;
    $seq =~ s/\s+//g;
    $bio_seq->seq( uc( $seq ) );
    $bio_seq->display_id( $recall_file->basename );

    my $cleaned_variant_seq_file = $self->base_dir->file('variant_seq.fa')->absolute;
    my $cleaned_variant_seqio = Bio::SeqIO->new( -fh => $cleaned_variant_seq_file->openw, -format => 'fasta' );
    $cleaned_variant_seqio->write_seq( $bio_seq );

    $self->variant_seq_file( $cleaned_variant_seq_file );

    return;
}

=head2 create_ref_seq_file

Create a reference sequence file for target region.

=cut
sub create_ref_seq_file {
    my ( $self ) = @_;

    my $target_string
        = $self->target_chr . ':'
        . ( $self->target_start - 300 ) . '-'
        . ( $self->target_end + 300 );
    my @samtools_faidx_cmd = (
        $SAMTOOLS_CMD,
        'faidx',                                  # mpileup command
        $BWA_REF_GENOMES{ lc( $self->species ) }, # reference genome file, faidx-indexed
        $target_string
    );

    $self->log->debug( "samtools faidx command: " . join( ' ', @samtools_faidx_cmd ) );
    my $ref_seq_file = $self->work_dir->file('ref_seq.fa')->absolute;
    my $log_file = $self->work_dir->file( 'samtools_faidx.log' )->absolute;
    run( \@samtools_faidx_cmd,
        '>',  $ref_seq_file->stringify,
        '2>', $log_file->stringify
    ) or die(
            "Failed to run samtools faidx command, see log file: $log_file" );

    if ( $self->target_strand == -1 ) {
        my $bio_seqio = Bio::SeqIO->new( -fh => $ref_seq_file->openr, -format => 'fasta' );
        my $revcomp_bio_seq = $bio_seqio->next_seq->revcom;

        my $ref_seq_revcomp_file = $self->work_dir->file('ref_seq_revcomp.fa')->absolute;
        my $bio_seqio_revcomp = Bio::SeqIO->new( -fh => $ref_seq_revcomp_file->openw, -format => 'fasta' );
        $bio_seqio_revcomp->write_seq( $revcomp_bio_seq );

        $self->ref_seq_file( $ref_seq_revcomp_file );
    }
    elsif ( $self->target_strand == 1 ) {
        $self->ref_seq_file( $ref_seq_file );
    }
    else {
        die( 'Invalid target strand: ' . $self->target_strand );
    }

    return;
}

__PACKAGE__->meta->make_immutable;

1;

__END__
