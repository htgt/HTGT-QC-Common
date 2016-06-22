package HTGT::QC::Util::ZipSequences;

use strict;
use warnings FATAL => 'all';

use Sub::Exporter -setup => {
    exports => [ 'zip_sequences' ]
};

use Bio::SeqIO;
use File::Temp;
use MooseX::Params::Validate;
use MooseX::Types::Path::Class;
use Path::Class;
use YAML::Any;
use Log::Log4perl ':easy';

sub zip_sequences {

    my %params = validated_hash(
        \@_,
        run_id          => { isa => 'Str' },
        synvec_dir      => { isa => 'Path::Class::Dir' },
        output_file     => { isa => 'Path::Class::File' },
        seq_reads       => { isa => 'HashRef[Bio::SeqI]' },
        post_filter_dir => { isa => 'Path::Class::Dir' },
    );

    INFO( "Zipping up sequences" );

    my $tmp_dir = File::Temp->newdir( DIR => $params{synvec_dir}->parent );
    my $out_dir = dir( $tmp_dir )->subdir( $params{run_id} );
    $out_dir->mkpath;
    
    my @query_wells;
    
    for my $query_dir ( $params{post_filter_dir}->children ) {
        for my $target_yaml ( $query_dir->children ) {
            my ( $query_well, $target_id, $primers ) = parse_analysis( $target_yaml );
            my $this_dir = $out_dir->subdir( $query_well )->subdir( $target_id );
            $this_dir->mkpath;
            my $target_gbk = _target_gbk( $params{synvec_dir}, $target_id );
            link $target_gbk, $this_dir->file( 'target.gbk' );
            my $primer_reads = _reads_for_primers( $primers, $params{seq_reads} );
            while ( my ( $primer, $bio_seq ) = each %{$primer_reads} ) {
                my $seq_io = Bio::SeqIO->new(
                    -fh     => $this_dir->file( $primer . '.fasta' )->openw,
                    -format => 'fasta'
                );
                $seq_io->write_seq( $bio_seq );
            }
        }
    }

    chdir( $tmp_dir ) or die "chdir $tmp_dir: $!";
    system( 'zip', '-r', $params{output_file}, $params{run_id} );
    chdir( ".." );
}

sub _reads_for_primers {
    my ( $primers, $seq_reads ) = @_;

    my %reads_for_primers;

    for my $primer ( keys %{$primers} ) {
        my $cigar = $primers->{$primer}->{cigar};
        next unless $cigar and keys %{$cigar} > 0;
        my $query_id = $cigar->{query_id};
        my $this_read_seq = $seq_reads->{$query_id}
            or LOGDIE "Failed to retrieve read $query_id";
        $reads_for_primers{ $primer } = $this_read_seq;
    }

    return \%reads_for_primers;
}
    
sub _target_gbk {
    my ( $synvec_dir, $target_id ) = @_;

    my $gbk = $synvec_dir->file( $target_id . '.gbk' );
    -f $gbk or LOGDIE( "File not found: $gbk" );

    return $gbk->stringify;
}

sub parse_analysis {
    my $target_yaml = shift;

    my $analysis = YAML::Any::LoadFile( $target_yaml );

    return @{$analysis}{ qw( query_well target_id primers ) };
}

1;

__END__

