package MyTest::Util::WriteConfFile;

use strict;
use warnings FATAL => 'all';

use Sub::Exporter -setup => {
    exports => [ qw( write_conffile ) ],
    groups  => {
        default => [ qw( write_conffile ) ]
    }
};

use File::Temp;

sub write_conffile {
    my $conffile = File::Temp->new;
    my $conf_data = do { local $/ = undef; <DATA> };
    $conffile->print( $conf_data );
    $conffile->close;
    return $conffile;
}

1;

__DATA__
GLOBAL {
    basedir = '/nfs/team87/data/qc/work'
}

RUNNER {
    basedir = '/nfs/team87/data/qc/runner'    
    max_parallel = 10
}       

alignment_regions {

    3arm-72-80 = {
        expected_strand = '-',
        start = { primary_tag = 'misc_feature', note = '3 arm', start = 0 }
        end   = { primary_tag = 'misc_feature', note = '3 arm', end = 0 }
        min_match_length = '72/80'
        genomic = 1
    }

    3arm-120-150 = {
        expected_strand = '-',
        start = { primary_tag = 'misc_feature', note = '3 arm', start = 0 }
        end   = { primary_tag = 'misc_feature', note = '3 arm', end = 0}
        min_match_length = '120/150'
        genomic = 1
    }

    3p-art-intron-72-80 = {
        expected_strand = '+',
        start = { primary_tag = 'intron', note = "3' Ifitm2 intron", start = 0 }
        end   = { primary_tag = 'intron', note = "3' Ifitm2 intron", end = 100 }
        min_match_length = '72/80'
        genomic = 0
    }

    3p-art-intron-90pct = {
        expected_strand = '+',
        start = { primary_tag = 'intron', note = "3' Ifitm2 intron", start = 100 }
        end   = { primary_tag = 'intron', note = "3' Ifitm2 intron", end = 0 }
        min_match_pct = 90
        genomic = 0
    }

    3p-art-intron-exon50-exact = {
        expected_strand = '+',
        start = { primary_tag = 'intron', note = "3' Ifitm2 intron", end = -19 }
        end   = { primary_tag = 'intron', note = "3' Ifitm2 intron", end = +50 }
        min_match_length = 70
        genomic = 1
    }

    3p-cassette-genomic1000-72-80 = {
        expected_strand = +
        start = { primary_tag = 'misc_feature', note = 'Synthetic Cassette', end = 1 }
        end   = { primary_tag = 'misc_feature', note = 'Synthetic Cassette', end = 1000 }
        min_match_length = '72/80'
        genomic = 1
    }

    3p-cassette-genomic20-80pct = {
        expected_strand = +
        start = { primary_tag = 'misc_feature', note = "Synthetic Cassette", end = -50 }
        end   = { primary_tag = 'misc_feature', note = "Synthetic Cassette", end = +19 }
        min_match_pct = 80
        genomic = 1
    }
    
    3p-cassette-genomic30-90pct = {
        expected_strand = '+',
        start = { primary_tag = 'misc_feature', note = 'Synthetic Cassette', end = -50 }
        end   = { primary_tag = 'misc_feature', note = 'Synthetic Cassette', end = +30 }
        min_match_pct = 90
        genomic = 1
    }

    3p-cassette-genomic50-80pct = {
        expected_strand = '+',
        start = { primary_tag = 'misc_feature', note = "Synthetic Cassette", end = -19 }
        end   = { primary_tag = 'misc_feature', note = "Synthetic Cassette", end = +50 }
        min_match_pct = 80
        genomic = 1
    }

    3p-cassette-genomic60-90pct = {    
        expected_strand = '+',
        start = { primary_tag = 'misc_feature', note = 'Synthetic Cassette', end = -19 }
        end   = { primary_tag = 'misc_feature', note = 'Synthetic Cassette', end = +60 }
        min_match_pct = 90
        genomic = 1
    }

    5arm-45-50 = {
        expected_strand = '+',
        start = { primary_tag = 'misc_feature', note = '5 arm', start = 0 }
        end   = { primary_tag = 'misc_feature', note = '5 arm', end = 0}
        min_match_length = '45/50'
        genomic = 1
    }

    5arm-72-80 = {
        expected_strand = '+',
        start = { primary_tag = 'misc_feature', note = '5 arm', start = 0 }
        end   = { primary_tag = 'misc_feature', note = '5 arm', end = 0}
        min_match_length = '72/80'
        genomic = 1
    }

    5p-art-intron-72-80 = {
        expected_strand = '-',
        start = { primary_tag = 'intron', note = "5' Ifitm2 intron", start = -100 }
        end   = { primary_tag = 'intron', note = "5' Ifitm2 intron", end = 0 }
        min_match_length = 72/80
        genomic = 0
    }
    
    5p-art-intron-90pct = {
        expected_strand = '-',
        start = { primary_tag = 'intron', note = "5' Ifitm2 intron", start = 0 }
        end   = { primary_tag = 'intron', note = "5' Ifitm2 intron", end = -70 }        
        min_match_pct = 90
        genomic = 0
    }

    5p-art-intron-exon50-exact = {
        expected_strand = '-',
        start = { primary_tag = 'intron', note = "5' Ifitm2 intron", start = -50 }
        end   = { primary_tag = 'intron', note = "5' Ifitm2 intron", start = +19 }
        min_match_length = 70
        genomic = 1
    }
    
    5p-cassette-genomic50-80pct = {
        expected_strand = '-',
        start = { primary_tag = 'misc_feature', note = "Synthetic Cassette", start = -50 }
        end   = { primary_tag = 'misc_feature', note = "Synthetic Cassette", start = +19 }
        min_match_pct = 80
        genomic = 1
    }

    5p-cassette-genomic60-90pct = {
        expected_strand = '-',
        start = { primary_tag = 'misc_feature', note = 'Synthetic Cassette', start = -60 }
        end   = { primary_tag = 'misc_feature', note = 'Synthetic Cassette', start = +19 }
        min_match_pct = 90
        genomic = 1
    }

    cassette-72-80 = {
        expected_strand = '-',
        start = { primary_tag = 'misc_feature', note = 'Synthetic Cassette', start = 0 },
        end   = { primary_tag = 'misc_feature', note = 'Synthetic Cassette', end = 0 }
        min_match_length = '72/80'
        genomic = 0
    }

    cre-90-100 = {
        expected_strand = '+'
        start = { primary_tag = 'misc_feature', label = 'Cre', start = 0 }
        end   = { primary_tag = 'misc_feature', label = 'Cre', end   = 0 }
        min_match_length = 90/100
        genomic = 0
    }
    
    fchk-prefix-90pct = {
        expected_strand = +        
        start = { primary_tag = 'misc_feature', note => 'FCHK QC prefix region', start = 0 }
        end   = { primary_tag = 'misc_feature', note => 'FCHK QC prefix region', end   = 0 }
        min_match_pct = 90
        genomic = 0
    }

    fchk-critical-90pct = {
        expected_strand = +        
        start = { primary_tag = 'misc_feature', note => 'FCHK QC critical region', start = 0 }
        end   = { primary_tag = 'misc_feature', note => 'FCHK QC critical region', end   = 0 }
        min_match_pct = 90
        genomic = 0
    }

    fchk-critical-no-indel = {
        expected_strand = +        
        start = { primary_tag = 'misc_feature', note => 'FCHK QC critical region', start = 0 }
        end   = { primary_tag = 'misc_feature', note => 'FCHK QC critical region', end   = 0 }
        ensure_no_indel = 1
        genomic = 0
    }

    fchk-suffix-90pct = {
        expected_strand = +        
        start = { primary_tag = 'misc_feature', note => 'FCHK QC suffix region', start = 0 }
        end   = { primary_tag = 'misc_feature', note => 'FCHK QC suffix region', end   = 0 }
        min_match_pct = 90
        genomic = 0
    }
    
    target-region-fwd-72-80 = {
        expected_strand = '+',
        start = { primary_tag = 'misc_feature', note = 'Critical Region', start = 0 },
        end   = { primary_tag = 'misc_feature', note = 'Critical Region', end = 0 }
        min_match_length = '72/80'
        genomic = 1
    }
    
    target-region-rev-72-80 = {
        expected_strand = '-',
        start = { primary_tag = 'misc_feature', note = 'Critical Region', start = 0 },
        end   = { primary_tag = 'misc_feature', note = 'Critical Region', end = 0 }
        min_match_length = '72/80'
        genomic = 1
    }

    target-region-45-50 = {
        expected_strand = '-',
        start = { primary_tag = 'misc_feature', note = 'Critical Region', start = 0 },
        end   = { primary_tag = 'misc_feature', note = 'Critical Region', end = 0 }
        min_match_length = '45/50'
        genomic = 1
    }
}

%macro $fchk 'fchk-prefix-90pct AND fchk-critical-90pct AND fchk-critical-no-indel AND fchk-suffix-90pct'

profile eucomm-post-cre {
    vector_stage = intermediate
    pre_filter_min_score = 2000
    post_filter_min_primers = 1
    primers = {
        LR = target-region-rev-72-80
        Z1 = 5p-cassette-genomic50-80pct
        Z2 = 3p-cassette-genomic50-80pct
    }
    pass_condition = '(Z1 OR Z2) AND LR'
}

profile eucomm-promoter-driven-post-gateway {
    vector_stage = final
    pre_filter_min_score = 3000
    post_filter_min_primers = 2
    primers = {
        L1 = 5p-cassette-genomic60-90pct
        LR = target-region-rev-72-80
        PNF = 3p-cassette-genomic60-90pct
        R3 = 5arm-72-80
    }    
    pass_condition = 'LR AND (L1 OR (R3 AND PNF))'
}

profile eucomm-promoter-driven-pre-escell {
    vector_stage = final
    pre_filter_min_score = 1000
    post_filter_min_primers = 1
    check_design_loc = 1
    primers = {
        LR = target-region-rev-72-80
        PNF = 3p-cassette-genomic60-90pct
    }
    pass_condition = 'LR OR PNF'
}

profile artificial-intron-post-cre {
    vector_stage = intermediate
    pre_filter_min_score = 5000
    post_filter_min_primers = 2
    primers = {
        LR = target-region-rev-72-80
        R1R = 5p-art-intron-exon50-exact
        R2R = 3p-art-intron-exon50-exact
        R3 = 5arm-72-80
        Z1 = 5p-art-intron-exon50-exact
        Z2 = 3p-art-intron-exon50-exact
    }    
    pass_condition = '(R1R OR Z1) AND (R2R OR Z2) AND LR AND R3'
}

profile artificial-intron-post-gateway {
    vector_stage = final
    pre_filter_min_score = 7000
    post_filter_min_primers = 2
    primers = {
        FCHK = "$fchk"
        L1 = '5p-art-intron-exon50-exact AND 5p-art-intron-90pct'
        LR = target-region-rev-72-80
        PNF = '3p-art-intron-exon50-exact AND 3p-art-intron-90pct'
        R1R = '5p-art-intron-exon50-exact AND 5p-art-intron-90pct'
        R2R = '3p-art-intron-exon50-exact AND 3p-art-intron-90pct'
        R3 = 5arm-45-50
    }        
    pass_condition = '(L1 OR R1R) AND (PNF OR R2R) AND LR AND FCHK'
}

profile artificial-intron-pre-escell {
    vector_stage = final
    pre_filter_min_score = 1000
    post_filter_min_primers = 1
    check_design_loc = 1
    primers = {
        LR = target-region-rev-72-80
        PNF = '3p-art-intron-exon50-exact AND 3p-art-intron-90pct'
    }
    pass_condition = 'LR OR PNF'
}

profile homozygous-post-cre {
    vector_stage = intermediate
    check_design_loc = 1
    pre_filter_min_score = 5000
    post_filter_min_primers = 2
    primers = {
        LR = target-region-rev-72-80
        R3 = 5arm-72-80
        R4 = 3arm-72-80
        Z1 = 5p-cassette-genomic50-80pct
        Z2 = 3p-cassette-genomic50-80pct
    }    
    pass_condition = 'LR AND (R3 OR Z1) AND (Z1 OR Z2) AND (Z2 OR R4)'
}

profile promoterless-homozygous-first-allele-post-gateway {
    vector_stage = final
    check_design_loc = 1
    pre_filter_min_score = 5000
    post_filter_min_primers = 2
    primers = {
        FCHK = "$fchk"
        L1 = 5p-cassette-genomic60-90pct
        LR = target-region-rev-72-80
        PNF = 3p-cassette-genomic60-90pct
        R3 = 5arm-72-80
        R4 = 3arm-72-80
    }
    pass_condition = 'LR AND FCHK AND (PNF OR R4) AND (L1 OR R3)'
}

profile promoterless-homozygous-first-allele-post-gateway-no-loc {
    vector_stage = final
    check_design_loc = 0
    pre_filter_min_score = 5000
    post_filter_min_primers = 2
    primers = {
        FCHK = "$fchk"
        L1 = 5p-cassette-genomic60-90pct
        LR = target-region-rev-72-80
        PNF = 3p-cassette-genomic60-90pct
        R3 = 5arm-72-80
        R4 = 3arm-72-80
    }
    pass_condition = 'LR AND FCHK AND (PNF OR R4) AND (L1 OR R3)'
}

profile homozygous-second-allele-pre-cre {
    vector_stage = final
    check_design_loc = 1
    pre_filter_min_score = 2000
    post_filter_min_primers = 2
    primers = {
        BBR = 3p-cassette-genomic1000-72-80
        LR = target-region-rev-72-80
        R3 = 5arm-72-80
        T3 = 5arm-72-80
    }
    pass_condition = 'LR AND (T3 OR R3) AND BBR'
}

profile homozygous-second-allele-pre-cre-no-loc {
    vector_stage = final
    check_design_loc = 0
    pre_filter_min_score = 2000
    post_filter_min_primers = 2
    primers = {
        BBR = 3p-cassette-genomic1000-72-80
        LR = target-region-rev-72-80
        R3 = 5arm-72-80
        T3 = 5arm-72-80
    }
    pass_condition = 'LR AND (T3 OR R3) AND BBR'
}

profile promoterless-homozygous-second-allele-post-gateway {
    vector_stage = final
    apply_cre = 1
    check_design_loc = 1    
    primers = {
        FCHK = "$fchk"
        L1 = 5p-cassette-genomic60-90pct
        LR = cassette-72-80
        R3 = 5arm-72-80
        R4 = 3arm-72-80
    }    
    pass_condition = 'R4 AND FCHK AND LR AND (L1 OR R3)'
}

profile promoterless-homozygous-second-allele-post-gateway-no-loc {
    vector_stage = final
    apply_cre = 1
    check_design_loc = 0
    primers = {
        FCHK = "$fchk"
        L1 = 5p-cassette-genomic60-90pct
        LR = cassette-72-80
        R3 = 5arm-72-80
        R4 = 3arm-72-80
    }    
    pass_condition = 'R4 AND FCHK AND LR AND (L1 OR R3)'
}

profile promoter-homozygous-second-allele-post-gateway {
    vector_stage = final
    apply_cre = 1
    check_design_loc = 1    
    primers = {
        BBR = 3p-cassette-genomic1000-72-80
        LR = cassette-72-80
        R3 = 5arm-72-80
        T3 = 5arm-72-80
    }    
    pass_condition = 'LR AND (T3 OR R3) AND BBR'
}

profile promoter-homozygous-second-allele-post-gateway-no-loc {
    vector_stage = final
    apply_cre = 1
    check_design_loc = 0
    primers = {
        BBR = 3p-cassette-genomic1000-72-80
        LR = cassette-72-80
        R3 = 5arm-72-80
        T3 = 5arm-72-80
    }    
    pass_condition = 'LR AND (T3 OR R3) AND BBR'
}

profile L3L4-2w-gateway {
    vector_stage = intermediate
    check_design_loc = 1
    pre_filter_min_score = 1000
    post_filter_min_primers = 1
    primers = {
        SP6 = 3arm-120-150
    }
    pass_condition = 'SP6'
}

profile L3L4-2w-gateway-no-loc {
    vector_stage = intermediate
    check_design_loc = 0
    pre_filter_min_score = 1000
    post_filter_min_primers = 1
    primers = {
        SP6 = 3arm-120-150
    }
    pass_condition = 'SP6'
}

profile eucomm-tools-cre-post-cre {
    vector_stage = intermediate
    pre_filter_min_score = 1000
    post_filter_min_primers = 1    
    primers = {
        Z1 = 5p-cassette-genomic50-80pct
        Z2 = 3p-cassette-genomic50-80pct
    }
    pass_condition = 'Z1 OR Z2'
}

profile eucomm-tools-cre-post-gateway {
    vector_stage = final
    pre_filter_min_score = 3000
    post_filter_min_primers = 2
    primers = {
        FCHK = "$fchk"
        L1 = 5p-cassette-genomic60-90pct
        PPA1 = 3p-cassette-genomic60-90pct
    }    
    pass_condition = 'FCHK AND (L1 OR  PPA1)'
}

profile artificial-intron-es-cell {
    vector_stage = allele
    pre_filter_min_score = 1000
    post_filter_min_primers = 1
    primers = {
        LFR = target-region-rev-72-80
        LR = target-region-rev-72-80
        LRR = 3arm-72-80
        R1R = 5p-art-intron-72-80
        R2R = 3p-art-intron-72-80
    }    
    pass_condition = 'LR AND LRR AND LFR AND R1R AND R2R'
}

profile cre-bac-recom {
    vector_stage = final
    pre_filter_min_score = 4000
    post_filter_min_primers = 3
    primers = {
        bpA = 3p-cassette-genomic60-90pct
        En2 = 5p-cassette-genomic60-90pct
        EYF1 = cre-90-100
        SP6 = 5arm-72-80
        T7 = 3arm-72-80
    }        
    pass_condition = 'SP6 AND T7 AND EYF1 AND En2 AND bpA'
}

profile cre-bac-recom-rev {
    vector_stage = final
    pre_filter_min_score = 4000
    post_filter_min_primers = 3
    primers = {
        bpA = 3p-cassette-genomic60-90pct
        En2 = 5p-cassette-genomic60-90pct
        EYF1 = cre-90-100
        SP6 = 3arm-72-80
        T7 = 5arm-72-80
    }        
    pass_condition = 'SP6 AND T7 AND EYF1 AND En2 AND bpA'
}

profile cre-es-cell {
    vector_stage = allele
    pre_filter_min_score = 1000
    post_filter_min_primers = 1
    primers = {
        LFR = target-region-rev-72-80
        R2R = target-region-fwd-72-80
    }
    pass_condition = 'LFR AND R2R'
}
