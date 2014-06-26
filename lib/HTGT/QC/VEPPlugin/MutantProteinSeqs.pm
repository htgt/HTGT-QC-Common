package HTGT::QC::VEPPlugin::MutantProteinSeqs;
## no critic(RequireUseStrict,RequireUseWarnings)
{
    $HTGT::QC::VEPPlugin::MutantProteinSeqs::VERSION = '0.020';
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

use lib '/opt/t87/global/software/ensembl-tools-release-75/scripts/variant_effect_predictor';
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

    # Deal with non frameshift variants, look at ProteinSeqs plugin for this
    if(grep {$_->SO_term eq 'frameshift_variant'} @ocs) {
        $self->setup_files unless exists $self->{ref_file};

        # can't do it for splice sites
        return {} if grep {$_->SO_term =~ /splice/} @ocs;

        #A TranscriptVariation object represents a variation feature which is in close
        #proximity to an Ensembl transcript. A TranscriptVariation object has several
        #attributes which define the relationship of the variation to the transcript.
        my $tv = $tva->transcript_variation;

        # Bio::EnsEMBL::Transcript object
        my $tr = $tv->transcript;
        my $id = $tr->stable_id;

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

        my $before_var_count = $low_pos == $last_complete_codon ? 0 : (( $low_pos - $last_complete_codon ) +  1) - ( $is_insertion ? 0 : 1 );
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

        $self->print_fasta($translation, $id, $self->{ref_file}) unless $self->{printed_ref}->{$id}++;
        $self->print_fasta($new_pep, $id, $self->{mut_file});

        return {};
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

sub print_fasta {
    my ($self, $peptide, $id, $fh) = @_;

    # get rid of any trailing newline
    chomp $peptide;

    # print the sequence
    print $fh ">$id\n$peptide\n";

    return;
}

1;

