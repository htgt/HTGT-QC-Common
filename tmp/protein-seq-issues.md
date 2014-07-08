VARIANT PROTEIN SEQUENCE GENERATION
===================================

PROBLEM: Produce mutant protein sequence for crispr es qc when we have damage

# NOTES
* Do we can about SNPs / strings of mismatches when producing mutant protein
* Are we only going to care about showing mutant protein for qc with INDEL damage in critical region?

# CURRENT SOLUTION
* Use a custom VEP plugin ( code take from Downstream and ProteinSeq plugins from Ensembl ).
* This produces a reference and mutant protein sequence file.

## PROBLEM
* It only works on one variant at a time, no way I can see to get around with within the plugin architecture.
* So it works okay when we have one insertion / deletion in the critical region.
* If we have multiple INDELS it will produce 2 protein sequences.
* Also deals with mismatches seperately.

# POSSIBLE SOLUTIONS

* Accept way it is now, not good for the cases where we have multiple variants in critical region.

* Try to merge INDELS in critical region.
    * Can only do this if we don't care about mismatches / SNP's 
    * Not sure if this will work and how good it will be merging indels that are very spaced apart...

* Try to produce a consensus fasta sequence from the vcf file, then generate protein sequence from this.
    * There are tools to take vcf and produce consensus fasta files.
    * Need to take mutant fasta file and produce protein sequence.. this has its own complications
    * Need to know gene + transcript ?
    




