package HTGT::QC::Constants;
## no critic(RequireUseStrict,RequireUseWarnings)
{
    $HTGT::QC::Constants::VERSION = '0.050';
}
## use critic

use strict;
use warnings FATAL => 'all';

use base 'Exporter';

use Const::Fast;

BEGIN {
    our @EXPORT_OK = qw(
        $BWA_MEM_CMD
        $SAMTOOLS_CMD
        $BCFTOOLS_CMD
        $VEP_CMD
        $VEP_CACHE_DIR
        %BWA_REF_GENOMES
        %CURRENT_ASSEMBLY
    );
    our %EXPORT_TAGS = ();
}

const our $BWA_MEM_CMD  => $ENV{BWA_MEM_CMD} //
    '/software/vertres/bin-external/bwa-0.7.5a-r406/bwa';
const our $SAMTOOLS_CMD => $ENV{SAMTOOLS_CMD} //
    '/software/vertres/bin-external/samtools-0.2.0-rc8/bin/samtools';
const our $BCFTOOLS_CMD => $ENV{BCFTOOLS_CMD} //
    '/software/vertres/bin-external/samtools-0.2.0-rc8/bin/bcftools';
const our $VEP_CMD => $ENV{VEP_CMD} //
    '/opt/t87/global/software/ensembl-tools-release-80/scripts/variant_effect_predictor/variant_effect_predictor.pl';
const our $VEP_CACHE_DIR => $ENV{VEP_CACHE_DIR} //
    '/lustre/scratch117/core/corebio/blastdb/Ensembl/vep';
#    '/lustre/scratch109/blastdb/Ensembl/vep';

const our %BWA_REF_GENOMES => (
    human => ( $ENV{BWA_REF_GENOME_HUMAN_FA} //
        '/lustre/scratch117/sciops/team87/blastdb/Human/bwa/Homo_sapiens.GRCh38.dna.primary_assembly.clean_chr_names.fa'),
    mouse => ( $ENV{BWA_REF_GENOME_MOUSE_FA} //
        '/lustre/scratch117/sciops/team87/blastdb/Mouse/bwa/Mus_musculus.GRCm38.toplevel.clean_chr_names.fa'),
);

const our %CURRENT_ASSEMBLY => (
    Mouse => 'GRCm38',
    Human => 'GRCh38',
);

1;

__END__
