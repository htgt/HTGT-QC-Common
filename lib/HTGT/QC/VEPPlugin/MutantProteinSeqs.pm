package HTGT::QC::VEPPlugin::MutantProteinSeqs;
## no critic(RequireUseStrict,RequireUseWarnings)
{
    $HTGT::QC::VEPPlugin::MutantProteinSeqs::VERSION = '0.050';
}
## use critic


=head1 NAME

HTGT::QC::VEPPlugin::MutantProteinSeqs

=head1 SYNOPSIS

perl variant_effect_predictor.pl -i variations.vcf --plugin HTGT::QC::VEPPlugin::MutantProteinSeqs

=head1 DESCRIPTION

This is a plugin for the Ensembl Variant Effect Predictor (VEP) that
predicts the downstream effects of a frameshift variant on the protein
sequence of a transcript. It is adapted from the Downstream plugin and
the ProteinSeqs plugin.

It provides the predicted mutant protein sequence and the reference
protein sequence in 2 seperate fasta files.

Note that changes in splicing are not predicted - only the existing
translateable (i.e. spliced) sequence is used as a source of
translation. Any variants with a splice site consequence type are
ignored.

=cut

use strict;
use warnings;

use lib '/opt/t87/global/software/ensembl-tools-release-78/scripts/variant_effect_predictor';
use Bio::EnsEMBL::Variation::Utils::BaseVepPlugin;

use base qw(Bio::EnsEMBL::Variation::Utils::BaseVepPlugin);

sub version {
    return '2.5';
}

sub feature_types {
    return ['Transcript'];
}

sub variant_feature_types {
    return ['VariationFeature'];
}

sub run {
    my ($self, $tva) = @_;

    my @ocs = @{$tva->get_all_OverlapConsequences};
    #print STDERR "MutantProteinSeqs Plugin: consequence SO terms: "
        #. ( join ",", map { $_->SO_term } @ocs ) . "\n";

    if(grep {$_->SO_term eq 'frameshift_variant'} @ocs) {
        $self->frameshift_variant( $tva, \@ocs );
    }
    elsif (my $mut_aa = $tva->peptide) {
        $self->non_frameshift_variant( $tva, $mut_aa );
    }

    return {};
}

sub setup_files {
    my $self = shift;

    my $base_dir = $self->params->[0] || '';

    open( $self->{ref_file}, '>', $base_dir . 'reference.fa' ) or die "Failed to open reference.fa";
    open( $self->{mut_file}, '>', $base_dir . 'mutated.fa' ) or die "Failed to open mutated.fa";

    return;
}

# Modified from Downstream VEP plugin
sub frameshift_variant {
    my ( $self, $tva, $ocs ) = @_;

    $self->setup_files unless exists $self->{ref_file};

    # can't do it for splice sites
    return if grep {$_->SO_term =~ /splice/} @{ $ocs };

    #A TranscriptVariation object represents a variation feature which is in close
    #proximity to an Ensembl transcript. A TranscriptVariation object has several
    #attributes which define the relationship of the variation to the transcript.
    my $tv = $tva->transcript_variation;

    # Bio::EnsEMBL::Transcript object
    my $tr = $tv->transcript;
    my $transcript_id = $tr->stable_id;

    #  Returns a sequence string which is the the translateable part of the transcripts sequence
    my $cds_seq = defined( $tr->{_variation_effect_feature_cache} )
                ? $tr->{_variation_effect_feature_cache}->{translateable_seq}
                : $tr->translateable_seq;

    # get the sequence to translate

    # start and end positions of variation
    my ($low_pos, $high_pos) = sort {$a <=> $b} ($tv->cds_start, $tv->cds_end);
    my $is_insertion         = $tv->cds_start > $tv->cds_end ? 1 : 0;
    my $last_complete_codon  = int($low_pos / 3) * 3;

    my $upto_var_seq = substr( $cds_seq, 0, ( $last_complete_codon - 1 ) );
    # seq between last codon and variation feature

    my $before_var_count
        = $low_pos == $last_complete_codon
        ? 0
        : ( ( $low_pos - $last_complete_codon ) + 1 ) - ( $is_insertion ? 0 : 1 );
    my $before_var_seq = substr( $cds_seq, $last_complete_codon - 1, $before_var_count );

    my $after_var_seq = substr($cds_seq, $high_pos - ($is_insertion ? 1 : 0) );
    my $to_translate  = $upto_var_seq . $before_var_seq . $tva->feature_seq . $after_var_seq;
    $to_translate     =~ s/\-//g;

    # create a bioperl object
    my $codon_seq = Bio::Seq->new(
      -seq      => $to_translate,
      -moltype  => 'dna',
      -alphabet => 'dna'
    );

    # get codon table
    my $codon_table;
    if(defined($tr->{_variation_effect_feature_cache})) {
        $codon_table = $tr->{_variation_effect_feature_cache}->{codon_table} || 1;
    }
    else {
        my ($attrib) = @{$tr->slice->get_all_Attributes('codon_table')};
        $codon_table = $attrib ? $attrib->value || 1 : 1;
    }

    # translate
    my $new_pep = $codon_seq->translate(undef, undef, undef, $codon_table)->seq();
    # delete everything past stop codon
    $new_pep =~ s/\*.*/\*/;

    my $translation
        = defined( $tr->{_variation_effect_feature_cache} )
        && defined( $tr->{_variation_effect_feature_cache}->{peptide} )
        ? $tr->{_variation_effect_feature_cache}->{peptide}
        : $tr->translation->seq;

    my $translation_id = $tr->translation->stable_id;
    $self->print_fasta( $translation, $translation_id, $self->{ref_file} )
        unless $self->{printed_ref}->{$translation_id}++;
    $self->print_fasta($new_pep, $tva->hgvs_protein, $self->{mut_file});

    return;
}

# Taken from ProteinSeqs VEP plugin
sub non_frameshift_variant {
    my ( $self, $tva, $mut_aa ) = @_;
    $self->setup_files unless exists $self->{ref_file};

    # get the peptide coordinates
    my $tl_start = $tva->transcript_variation->translation_start;
    my $tl_end = $tva->transcript_variation->translation_end;

    # and our reference sequence
    ## no critic(Subroutines::ProtectPrivateSubs)
    my $ref_seq = $tva->transcript_variation->_peptide;
    ## use critic

    # splice the mutant peptide sequence into the reference sequence
    my $mut_seq = $ref_seq;
    substr($mut_seq, $tl_start-1, $tl_end - $tl_start + 1, $mut_aa);

    # print out our reference and mutant sequences
    my $translation_id = $tva->transcript->translation->stable_id;

    # only print the reference sequence if we haven't printed it yet
    $self->print_fasta($ref_seq, $translation_id, $self->{ref_file})
        unless $self->{printed_ref}->{$translation_id}++;

    # we always print the mutated sequence as each mutation may have
    # a different consequence
    $self->print_fasta($mut_seq, $tva->hgvs_protein, $self->{mut_file});

    return;
}

sub print_fasta {
    my ($self, $peptide, $id, $fh) = @_;

    # get rid of any trailing newline
    chomp $peptide;

    # print the sequence
    print $fh ">$id\n$peptide\n";

    return;
}

1;

