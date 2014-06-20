use strict;
use Bio::SeqIO;
use Bio::Seq;
use Bio::Seq::Quality;
use HTGT::Utils::EnsEMBL;

my $WORKDIR = 'work';
my $ens = HTGT::Utils::EnsEMBL->new();

# sample1.fa
#8:119612641-119613270

my $gene = shift;
my $species = shift;
my $left_crispr = shift;
my $right_crispr = shift;

my $read_file_name = shift;
my $chr;
my $start;
my $end;

# set up gene and crispr location (note - actual location of deletion seems out of wack with location of this crispr,
# so maybe I have the crispr wrong
if(!$gene){
	$gene = 'Adad2';
	$species = 'mouse';
	$left_crispr = 'CCTAGGACCGCTGAGCATGGGGT';
	$read_file_name = 'adad2_reads.fa';
}
#elsif(!$read_file_name){
#	$read_file_name = 'adad2_reads.fa';
#	$chr = '8';
#	$start = 119612641;
#	$end = 119613270; 
#}

# Fetch out location of gene, and find crispr in there
# Then subset sequence in a flank around putative crispr location
 
my $ens_gene = $ens->gene_adaptor->fetch_by_display_label($gene);
if(!$ens_gene){
	die "cant get gene by display label $gene\n";
}

my $chr = $ens_gene->seq_region_name;
my $start = $ens_gene->seq_region_start;
my $end = $ens_gene->seq_region_end;

#Fetch a region out of ensembl which is of interest - a few hundred bp around the expected crispr cut site 
#Remember where you got the slice (we have to adjust the vcf at the end)
my $sa = $ens->slice_adaptor;

#fetch out the sequence under the gene, but in the ens forward strand
my $gene_seq = $sa->fetch_by_region('chromosome', $chr, $start, $end )->seq;

#crispr pos is the offset of the crispr into the gene's sequence
my $crispr_pos = index($gene_seq, $left_crispr);
if(!$crispr_pos){
	die "gene $gene, ".$ens_gene->stable_id.", doesn't contain the crispr!\n";
}
print "old start / end $start - $end, crispr pos: $crispr_pos\n";

#fetch a +/- 300 bp flank around the putative crispr location
my $new_start = $start + $crispr_pos - 1 - 300;
my $new_end = $new_start + 600;

print "new start / end $start - $end\n";
$start = $new_start;
$end = $new_end;


#Now fetch out the actual target sequence (more tightly defined by the crispr location)
my $slice = $sa->fetch_by_region( 'chromosome', $chr, $start, $end );
my $target_seq = $slice->seq;

## All the above is just to get the sequence around the crispr...

my $target_name = "${WORKDIR}/$chr:${start}_${end}.fa";
my $target = Bio::Seq->new(-id => $target_name, -seq => $target_seq);
my $target_out = Bio::SeqIO->new(-file => ">${target_name}", -format => 'Fasta');
$target_out->write_seq($target);

#Index the target sequence
my $bwa_command = "/software/vertres/bin-external/bwa index $target_name";
print "$bwa_command\n";
open my $output, "$bwa_command |";
while (<$output>){
	print $_;
}

# This is roughly the sequence of commands executed below
# /software/vertres/bin-external/bwa index tp53_exon.fa
# /software/vertres/bin-external/bwa mem tp53_exon.fa tp53_a01.fq > tp53_a01_exon.sam
# /software/vertres/bin-external/samtools-0.2.0-rc7/bin/samtools mpileup -ug -f tp53_exon.fa tp53_a01_exon.bam | /software/vertres/bin-external/samtools-0.2.0-rc7/bin/bcftools call -Nvm - > tmp.vcf

my $in = Bio::SeqIO->new(-format    => 'fasta', -file=>$read_file_name);

my $count = 1;
while(my $seq = $in->next_seq){
	next unless $seq->id =~ /Adad/;
	align_and_call_variant($seq,$target_name);
	$count++;

	#if($count > 2){
	#	last;
	#}
}

sub align_and_call_variant {

	my $query_seq_fasta = shift;
	my $query_seq_name = $query_seq_fasta->id;

	# There are some query seqs which don't match the gene in the sample
	next unless $query_seq_name =~ /Adad/;

	my $target_name = shift;
	my $fastq_seq_name = "${WORKDIR}/${query_seq_name}.fq";

	#Make the single-seq fastq file
	my $raw_seq = $query_seq_fasta->seq;
	my $quality = "~" x length($raw_seq);
	my $query_seq_fq = Bio::Seq::Quality->new(
		-id => $query_seq_name,
		-qual => $quality,
		-seq => $raw_seq
	);
	my $out = Bio::SeqIO->new(-format => 'fastq', -file => ">$fastq_seq_name");
	$out->write_seq($query_seq_fq);
	

	#run bwa mem to align read against small local sequence 
	my $align_command = "/software/vertres/bin-external/bwa mem $target_name $fastq_seq_name > ${fastq_seq_name}_align.sam";

	print "$align_command\n";
	open my $output, "$align_command |";
	while (<$output>){
		print $_;
	}
	

    ## we want newer version of samtools ( rc8 )
	#run mpileup against sam output from bwa mem 
	my $mpileup_command = "/software/vertres/bin-external/samtools-0.2.0-rc7/bin/samtools mpileup -ug -Q 0 -f $target_name ${fastq_seq_name}_align.sam | /software/vertres/bin-external/samtools-0.2.0-rc7/bin/bcftools call -Nvm - > ${fastq_seq_name}.vcf";
	print "$mpileup_command\n";
	open my $output, "$mpileup_command |";
	while (<$output>){
		print $_;
	}

	#Now each vcf file has a reference position relative to the input small fasta file,
	#BUT we need to replace the chromosome (slice) with the full input chromosome, and 'bump' the reference base position
	#to be the one on the original genome
	open VCF, "<${fastq_seq_name}.vcf" or die "can't find working vcf file for $fastq_seq_name\n";
	open NEW_VCF, ">${fastq_seq_name}.genomic.vcf" or die "can't find working vcf file for $fastq_seq_name\n";
	while(<VCF>){
		chomp;
		if($_ =~ /^\#/){
			print NEW_VCF "$_\n";
			next;
		}else{
			next unless /INDEL;/;
			my ($chrom,$pos,@rest) = split/\t/;
			$chrom = $chr;
			$pos = $pos + $start - 1;
			my $rest = join "\t",@rest;
			print NEW_VCF "$chrom\t$pos\t$rest\n";
		}
	}

	#Now feed the new vcf file into VEP
	#perl /lustre/scratch110/sanger/vvi/ensembl-tools/scripts/variant_effect_predictor/variant_effect_predictor.pl --database --species mouse --force_overwrite -i work/A02_346501_2_Adad2_F1_6315_2FF.fq.genomic.vcf -o ${fastq_seq_name}.vep.csv
	my $vep_command = "perl /lustre/scratch110/sanger/vvi/ensembl-tools/scripts/variant_effect_predictor/variant_effect_predictor.pl --database --species mouse --force_overwrite -i ${fastq_seq_name}.genomic.vcf -o ${fastq_seq_name}.vep.csv";
	print "$vep_command\n";

	open my $output, "$vep_command |";
	open VEP_OUT, ">${fastq_seq_name}.vep_out";
	while(<$output>){
		print VEP_OUT $_;
	}
}
