package HTGT::QC::Util::FindSeq;

use strict;
use warnings FATAL => 'all';

use Sub::Exporter -setup => {
    exports => [ qw( find_seq ) ],
    groups => {
        default => [ qw( find_seq ) ]
    }
};

use Path::Class;
use Bio::SeqIO;
use Log::Log4perl ':easy';
use Carp 'confess';

sub find_seq {
    my ( $dir, $seq_id, $format ) = @_;

    DEBUG( "Searching $dir for $format sequence $seq_id" );    
    
    $dir = dir( $dir );
    
    my @candidate_files;
    if ( $format eq 'genbank' ) {
        if ( $dir->file( "$seq_id.gbk" )->stat ) {
            push @candidate_files, $dir->file( "$seq_id.gbk" );                                      
        }
        else {
            @candidate_files = grep /\.gbk$/, $dir->children;            
        }
    }
    elsif ( $format eq 'fasta' ) {
        if ( $dir->file( "$seq_id.fasta" )->stat ) {
            push @candidate_files, $dir->file( "$seq_id.fasta" );
        }
        else {
            @candidate_files = grep /\.fasta$/, $dir->children;            
        }
    }
    else {
        confess "Unrecognized format: '$format'";
    }

    for my $file ( @candidate_files ) {
        DEBUG( "Reading sequences from $file" );
        my $seq_io = Bio::SeqIO->new( -file => $file, -format => $format )
            or die "Error reading file $file";
        while ( my $seq = $seq_io->next_seq ) {
            ( my $this_seq_id = $seq->display_id ) =~ s/\s+.*$//;
            DEBUG( "Considering $this_seq_id" );
            if ( $this_seq_id eq $seq_id ) {
                DEBUG( "Found $seq_id in $file" );
                return $seq;
            }
        }
    }

    LOGDIE "Failed to locate sequence with id $seq_id";
}

1;

__END__
