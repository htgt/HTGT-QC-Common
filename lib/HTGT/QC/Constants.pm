package HTGT::QC::Constants;
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

const our $BWA_MEM_CMD  => $ENV{BWA_MEM_CMD}
    // '/software/vertres/bin-external/bwa-0.7.5a-r406/bwa';
const our $SAMTOOLS_CMD => $ENV{SAMTOOLS_CMD}
    // '/software/vertres/bin-external/samtools-0.2.0-rc8/bin/samtools';
const our $BCFTOOLS_CMD => $ENV{BCFTOOLS_CMD}
    // '/software/vertres/bin-external/samtools-0.2.0-rc8/bin/bcftools';
const our $VEP_CMD => $ENV{VEP_CMD}
    // '/opt/t87/global/software/ensembl-tools-release-78/scripts/variant_effect_predictor/variant_effect_predictor.pl';
const our $VEP_CACHE_DIR => $ENV{VEP_CACHE_DIR}
    // '/lustre/scratch109/blastdb/Ensembl/vep';
    #// '/lustre/scratch110/sanger/sp12/vep_cache';

const our %BWA_REF_GENOMES => (
    human => '/lustre/scratch109/blastdb/Users/team87/Human/bwa/Homo_sapiens.GRCh38.dna.primary_assembly.clean_chr_names.fa',
    mouse => '/lustre/scratch109/blastdb/Users/team87/Mouse/bwa/Mus_musculus.GRCm38.toplevel.clean_chr_names.fa',
    #human => '/lustre/scratch110/sanger/sp12/temp_ref_files/Human/bwa/Homo_sapiens.GRCh38.dna.primary_assembly.clean_chr_names.fa',
    #mouse => '/lustre/scratch110/sanger/sp12/temp_ref_files/Mouse/bwa/Mus_musculus.GRCm38.toplevel.clean_chr_names.fa',
);

const our %CURRENT_ASSEMBLY => (
    Mouse => 'GRCm38',
    Human => 'GRCh38',
);


1;

__END__
