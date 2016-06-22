package HTGT::QC::Util::FindSeqFeature;

use strict;
use warnings FATAL => 'all';

use Sub::Exporter -setup => {
    exports => [ qw( find_seq_feature find_seq_feature_loc ) ],
    groups => {
        default => [ qw( find_seq_feature ) ]
    }
};

use List::MoreUtils qw( any );
use Log::Log4perl ':easy';
use Data::Dump 'pp';

sub _is_match {
    my ( $str, $match ) = @_;

    return unless defined $str;
    
    if ( ref( $match ) eq 'Regexp' ) {
        return $str =~ $match;
    }
    else {
        return $str eq $match;
    }    
}

sub find_seq_feature {
    my ( $bio_seq, %wanted ) = @_;

    my @features;
    if ( my $primary_tag = delete $wanted{primary_tag} ) {
        @features = grep _is_match( $_->primary_tag, $primary_tag ), $bio_seq->get_SeqFeatures;
    }
    else {
        @features = $bio_seq->get_SeqFeatures;        
    }

    my @wanted;

 FEATURE:
    for my $feature ( @features ) {
        for my $tag ( keys %wanted ) {
            next FEATURE unless $feature->has_tag( $tag );
            next FEATURE unless any { _is_match( $_, $wanted{$tag} ) } $feature->get_tag_values( $tag );
        }
        push @wanted, $feature;
    }

    if ( wantarray ) {
        return @wanted;
    }
    elsif ( @wanted <= 1 ) {
        return shift @wanted;
    }
    else {
        LOGDIE "find_seq_feature found " . @wanted . " features matching " . pp( \%wanted );        
    }
}

sub find_seq_feature_loc {
    my ( $bio_seq, @wanted ) = @_;
    my $feature = find_seq_feature( $bio_seq, @wanted )
        or LOGDIE 'find_seq_feature_loc found no features in ' . $bio_seq->display_id . ' matching ' . pp( \@wanted );
    return $feature->location;
}
    
1;

__END__
