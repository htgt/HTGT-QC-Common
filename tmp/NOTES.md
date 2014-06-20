Crispr ES QC 
============

## VCF
* its binary form is BCF ( compressed or non compressed )

## BWA
* mapping low divergent sequences against large reference genome
* aln: designed for illumina sequence reads up to 100bp
* mem: align sequence reads from 70bp - 1Mbp 
* Comments suggest we should use mem where possible ( i.e. reads over 70bp )

## mpileup
* Generate a pileup of multiple reads using alignments to reference sequence.
* This pileup can be used for variant analysis / calling.
* Part of the samtools package
* output normally in pileup format, we want it in bcf ( binary call format ), which is a compressed binary format
    * -f to specify the reference genome
    * -Q minimum base quality ( set to 0 for now? )
    * -u like bcf but uncompressed ( good for piping )
    * -g output in bcf format

* automatically scans every position supported by an aligned read, computes all the possible genotypes supported by these reads, and then computes the probability that each of these genotypes is truly present in our sample.
* So uses all the reads to infer the true genotype ( in our case if damage or not )
* In our case only 2 reads ( forward and reverse primers )
* IDEA! - you can call mpileup and only specify a certain area of the reference genome ( so only the crispr region?? ) ( so we can use the whole human / mouse genome as the reference?? )

* collects summary information in the input BAMs, computes the likelihood of data given each possible genotype and stores the likelihoods in the BCF format ( see next point ). It does not call variants.
* Bcftools applies the prior and does the actual SNP / indel etc calling. It can also concatenate BCF files, index BCFs for fast random access and convert BCF to VCF. 

## bcftools call / view
* uses the genotype likelihoods generated from the previous mpileup step to call SNPs and indels, and outputs the all identified variants in the variant call format (VFC) 
* -N ?? not sure this does anything
* -v output varient sites only
* -m alternative model for multiallelic and rare-variant calling designed to overcome known limitations in -c calling model

## VEP
* The VEP determines the effect of your variants (SNPs, insertions, deletions, CNVs or structural variants) on genes, transcripts, and protein sequence, as well as regulatory regions
* Setup and still local script / cache to run this
* The vcf file vep needs expects chromosome names like 1,5,X etc, but the vcf files we produce seem to have complicated chromosome names
    * e.g. Chromosome:1:1:234234: ...
    * will need to clean up the vcf file or find a option to do this

## TODO
Install the following, make sure its latest version:
* samtools
* bcftools
* bwa
* ensemble vep ( and cache for human? )

Original reference genomes have long form chromosome names - can I make it smaller?

## STEPS
1. Grab reads for given crispr / well
2. Generate fasta file with target sequence ( 300 bp flanking the crispr region )
3. Index the target sequence ( why do we do this, and not just run against whole genome )
4. Run bwa mem to get alignment of reads against the target sequence
5. Output from last step is sam file, we may need sorted bam files for next step, if so do that

samtools view -b -S -o [output] [input]
samtools sort [input] [output]

6. Run mpileup of alignments against the target sequence
   samtools mpileup -ug -Q 0 -f [ref genome] [alignments sam file] > [ output.bcf ]

7. Run bcftools call to generate vcf files from the mpileup bcf output ( varient effect data )
   bcftools call -Nvm [bcf file] > [vcf file] 

8. Feed the vcf files into VEP to produce a csv file with varient data

## NOTES
* If the target file is just a section of the genome around the crispr site then the coordiantes 
  in the vcf file need to modified to make them genomic

## IDEA
* Run bwa mem against all the reads, then sort output by well to create individual sam files needed for next step
* maybe the bcftools stat / plot-vcfstats commands to create some visual output

## PROBLEMS
* We want some kind of visual representation of the deletion, possibly this can be made using the pileup file
    * we need the bcf file from mpileup, it will not produce both pileup and bcf.
    * can't seem to convert pileup to bcf or vice versa
    * do not want to run mpileup twice to produce both files
* Maybe we can use a alternate way to visualise deletion, not using a pileup file

* plot-vcfstats needs matplotlib python library, which it can't seem to find 

* need to tell if one or both reads has deletion, if just one ... ?
* what to do if we just have one read?
