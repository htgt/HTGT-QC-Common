package HTGT::QC::Util::DrawPileupAlignment;
## no critic(RequireUseStrict,RequireUseWarnings)
{
    $HTGT::QC::Util::DrawPileupAlignment::VERSION = '0.050';
}
## use critic


=head1 NAME

HTGT::QC::Util::DrawPileupAlignment

=head1 DESCRIPTION

Take a pileup file generated from very specific input and build up the aligned sequence
to display. Used to create aligned sequences of primer pair reads that cover area of potential
crispr damage.

The pileup file must consist of 2 reads, one forward and one reverse, that overlap the same area.

=cut

use Moose;
use MooseX::Types::Path::Class::MoreCoercions qw/AbsFile AbsDir/;
use Const::Fast;
use IPC::Run 'run';
use Bio::SeqIO;
use YAML::Any qw( DumpFile );
use HTGT::QC::Constants qw(
    $SAMTOOLS_CMD
    %BWA_REF_GENOMES
);
use namespace::autoclean;

with qw( MooseX::Log::Log4perl );

const my %INS_BASE_CODE => (
    N => 'J',
    A => 'L',
    T => 'P',
    C => 'Y',
    G => 'Z',
    X => 'X',
);

has species => (
    is       => 'ro',
    isa      => 'Str',
    required => 1,
);

has [ 'target_start', 'target_end' ] => (
    is       => 'ro',
    isa      => 'Int',
    required => 1,
);

has target_chr => (
    is       => 'ro',
    isa      => 'Str',
    required => 1,
);

has pileup_file => (
    is       => 'ro',
    isa      => AbsFile,
    required => 1,
    coerce   => 1,
);

has seqs => (
    is      => 'rw',
    isa     => 'HashRef',
    default => sub{ {} },
);

has insertions => (
    is      => 'rw',
    isa     => 'HashRef',
    default => sub{ {} },
);

has deletions => (
    is      => 'rw',
    isa     => 'HashRef',
    default => sub{ {} },
);

has active_reads => (
    is      => 'rw',
    isa     => 'HashRef',
    default => sub{ {} },
);

has [ 'first_read', 'second_read', 'last_active_read' ] => (
    is  => 'rw',
    isa => 'Str',
);

has [ 'genome_start', 'genome_end' ] => (
    is  => 'rw',
    isa => 'Int',
);

has current_position => (
    is               => 'ro',
    isa              => 'Num',
    traits           => [ 'Counter' ],
    default          => 0,
    handles          => {
        inc_position => 'inc',
    },
);

has dir => (
    is       => 'ro',
    isa      => AbsDir,
    coerce   => 1,
    required => 1,
);

=head2 calculate_pileup_alignment

Calculate the aligned sequences for the reads against the genome so we can build a
simple diagram that shows the reads to show the users.

Pilup is a tab delimited file, following data stored in each column:
0 = chromosome
1 = position ( 1 based )
2 = ref base
3 = read depth
4 = read bases
5 = base qualities

The read bases string can be interpreted as follows:
. = match to reference on forward strand
, = match to reference on reverse strand
AGCTN = mismatch on forward strand
agctn = mismatch on reverse strand
^ = start of read
$ = end of read
+4ACGT = insertion of sequence, 4 bases ACGT
-4CACC = deletion of sequence, 4 bases CACC

=cut
sub calculate_pileup_alignment {
    my ( $self ) = @_;
    my $fh = $self->pileup_file->openr() or die ('Can not open file: ' . $self->pileup_file->stringify);

    $self->log->info('Generate alignments from pileup file');
    my ( $chr, $genome_position, $ref, $depth, $reads, $quality, $last_genome_position );
    while ( <$fh> ) {
        chomp;
        ( $chr, $genome_position, $ref, $depth, $reads, $quality ) = split(/\t/);
        if ( $self->current_position == 0 ) {
            $self->calculate_read_positions( $reads );
            $self->genome_start( $genome_position );
        }
        else {
            if ( $last_genome_position != $genome_position - 1 ) {
                my $missing_genomic_seq
                    = $self->grab_genomic_seq( $last_genome_position + 1, $genome_position - 1 );
                $self->log->warn( 'Reads do not overlap, inserting missing genomic sequence' );
                my $length = length( $missing_genomic_seq );
                $self->seqs->{ref}     .= $missing_genomic_seq;
                $self->seqs->{forward} .= 'X' x $length;
                $self->seqs->{reverse} .= 'X' x $length;
            }
        }

        if ( $self->target_chr ne $chr ) {
            die( 'Expected chromosome ' . $self->target_chr . " in pileup, got $chr" );
        }

        my $read_array = $self->split_reads( $reads, $depth );
        $self->seqs->{ref} .= $ref;

        $self->build_sequences( $read_array, $ref, $depth );
        $self->inc_position;
        $last_genome_position = $genome_position;
    }
    $self->genome_end( $genome_position );

    #remove empty alignments
    for my $align_type ( qw( forward reverse ) ) {
        if ( $self->seqs->{$align_type} =~ /^X+$/ ) {
            delete $self->seqs->{$align_type};
        }
    }
    $self->parse_insertions;

    $self->create_output_files;

    return;
}

=head2 create_output_files

Create output files holding data required to build alignment text.

=cut
sub create_output_files {
    my ( $self ) = @_;

    my $alignments_file = $self->dir->file('alignment.txt')->absolute;
    my $output_fh = $alignments_file->openw;
    print $output_fh $_ . "\n" for values %{ $self->seqs };

    my %data;
    my $alignment_data_file = $self->dir->file('alignment_data.yaml')->absolute;
    $data{target_sequence_start} = $self->genome_start;
    $data{target_sequence_end}   = $self->genome_end;
    $data{insertions}            = $self->insertions;
    $data{deletions}             = $self->deletions;
    DumpFile( $alignment_data_file, \%data );

    return;
}

=head2 calculate_read_positions

Work out the positions of the forward and reverse reads in the pileup file.

=cut
sub calculate_read_positions {
    my ( $self, $read ) = @_;

    $self->log->debug('Calculate read positions in pileup');
    my $base;
    if ( $read =~ /^\^.(.)/ ) {
        $base = $1;
    }
    else {
        die ( "Can not calculate read positions: $read" );
    }

    if ( $base =~ /,/ || $base =~ /[actgn]/ ) {
        $self->first_read('reverse');
        $self->second_read('forward');
    }
    elsif ( $base =~ /\./ || $base =~ /[ACTGN]/ ) {
        $self->first_read('forward');
        $self->second_read('reverse');
    }
    else {
        die( "Can not calculate read positions: $base" );
    }

    return;
}

=head2 split_reads

Split the reads string from the pileup output into a array of
characters, one for each read, which indicates what is present at
this position for each read.

Strip out the special character sequences from the string and parse them:
Insertions: +[0-9]+[ACTGNactgn]+
    e.g +4ACTT
    Store in insertions hash.

Deletions: -[0-9]+[ACTGNactgn]+
    e.g. -2gg
    Just remove from string.

Start of read: ^.
    e.g. ^]
    Mark appropriate read has active.

End of read: $
    Mark appropriate read as inactive.

=cut
## no critic(ProhibitExcessComplexity)
sub split_reads {
    my ( $self, $reads_string, $read_depth ) = @_;

    return if $read_depth == 0;

    # deal with indels first, strip them out and store the insertions
    while ( $reads_string =~ /[-+](?<count>[0-9]+)/ ) {
        my $count = $+{count};
        $reads_string =~ s/(?<expr>[-+][0-9]+(?<seq>[A-za-z]{$count}))//;
        my $expr = $+{expr};
        my $seq = $+{seq};
        my $read = $seq =~ /^[ACTGN]+$/ ? 'forward' : 'reverse';
        if ( $expr =~ /^\+/ ) {
            push @{ $self->insertions->{$self->current_position} },{
                seq    => uc($seq),
                length => $count,
                read   => $read,
            };
        }
        elsif ( $expr =~ /^-/ ) {
            push @{ $self->deletions->{$self->current_position} },{
                seq    => uc($seq),
                length => $count,
                read   => $read,
            };
        }
    }

    # now deal with start / stops, need to strip them out and set active / inactive flags
    if ( $reads_string =~ /\^/ ) {
        # strip ^] from read string
        $reads_string =~ s/\^.//;
        if ( $read_depth == 1 ) {
            if ( $self->current_position == 0 ) {
                $self->active_reads->{ $self->first_read } = 1;
            }
            else {
                $self->active_reads->{$self->second_read} = 1;
            }
        }
        else {
            $self->active_reads->{$self->second_read} = 1;
            # in the unlikely case both reads start in same place
            if ( $reads_string =~ s/\^.// ) {
                $self->active_reads->{$self->first_read} = 1;
            }
        }
    }

    if ( $reads_string =~ /\$/ ) {
        if ( $read_depth == 2 ) {
            if ( $reads_string =~ /\$$/ ) {
                $self->active_reads->{$self->second_read} = 0;
            }
            else {
                $self->active_reads->{$self->first_read} = 0;
            }
        }
        else {
            # depth of one, only 1 active read
            if ( $self->active_reads->{forward} ) {
                $self->active_reads->{forward} = 0;
                $self->last_active_read('forward');
            }
            else {
                $self->active_reads->{reverse} = 0;
                $self->last_active_read('reverse');
            }
        }
        $reads_string =~ s/\$//g;
    }

    # if the read depth is one return it
    if ( $read_depth == 1 ) {
        die ( "String should only have 1 char: $reads_string"  ) if length($reads_string) != 1;
        return [ $reads_string ];
    }
    # otherwise split in 2 and return that ( should only be left with 2 chars in string )
    elsif ( $read_depth == 2 ) {
        die ( "String should only have 2 chars: $reads_string" )  if length($reads_string) != 2;
        return [ split('', $reads_string ) ];
    }
    else {
        die( "Read depth can only be 0, 1 or 2: $read_depth" );
    }

    return;
}
## use critic

=head2 build_sequences

Add appropriate characters to each read sequence string.

=cut
sub build_sequences {
    my ( $self, $read_array, $ref, $depth ) = @_;

    if ( $depth == 1 ) {
        $self->build_single_sequence( $read_array->[0], $ref );
    }
    elsif ( $depth == 2 ) {
        $self->seqs->{$self->first_read}  .= $self->calculate_base( $read_array->[0], $ref );
        $self->seqs->{$self->second_read} .= $self->calculate_base( $read_array->[1], $ref );
    }
    elsif ( $depth == 0 ) {
        $self->seqs->{forward} .= ' ';
        $self->seqs->{reverse} .= ' ';
    }
    return;
}

=head2 build_single_sequence

When only 1 read aligning to reference at given position need to add a space
character to the other inactive read.

=cut
sub build_single_sequence {
    my ( $self, $read, $ref ) = @_;

    if ( $self->active_reads->{forward} ) {
        $self->seqs->{forward} .= $self->calculate_base( $read, $ref );
        $self->seqs->{reverse} .= 'X';
    }
    elsif ( $self->active_reads->{reverse} ) {
        $self->seqs->{reverse} .= $self->calculate_base( $read, $ref );
        $self->seqs->{forward} .= 'X';
    }
    else {
        # end of reads
        if ( $self->last_active_read eq 'forward' ) {
            $self->seqs->{reverse}  .=  'X';
            $self->seqs->{forward} .= $self->calculate_base( $read, $ref );
        }
        else {
            $self->seqs->{forward}  .=  'X';
            $self->seqs->{reverse} .= $self->calculate_base( $read, $ref );
        }
    }
    return;
}

=head2 calculate_base

Calculate the character to be appended to the sequence string.

=cut
sub calculate_base {
    my ( $self, $read, $ref ) = @_;

    if ( $read =~ /[.,]/ ) {
        return $ref;
    }
    elsif ( $read =~ /^([A-Za-z])$/ ) {
        return lc($1);
    }
    elsif ( $read eq '*' ) {
        return '-';
    }
    else {
        die( "Not sure what to do with $read" );
    }
    return;
}

=head2 parse_insertions

Go through the insertion strings and insert them into the read and reference
sequences.

=cut
sub parse_insertions {
    my ( $self ) = @_;
    $self->log->debug('Parse insertions and place in alignment sequences');
    my @insert_positions = sort { $b <=> $a } keys %{ $self->insertions };

    for my $pos ( @insert_positions ) {
        my $inserts = $self->insertions->{$pos};
        if ( scalar( @{ $inserts } ) == 1 ) {
            if ( $inserts->[0]{read} eq 'forward' ) {
                $self->add_insertion( 'forward', $pos );
                $self->add_insertion( 'ref', $pos );
            }
            else {
                $self->add_insertion( 'reverse', $pos );
                $self->add_insertion( 'ref', $pos );
            }
        }
        elsif ( scalar( @{ $inserts } ) == 2 ) {
            $self->add_insertion( 'forward', $pos );
            $self->add_insertion( 'reverse', $pos );
            $self->add_insertion( 'ref', $pos );
        }
        else {
            die( "Too many insert sequences at position $pos: " . scalar( @{ $inserts } ) );
        }
    }
    return;
}

=head2 add_insertion

Push the insert sequence into the named sequence string.

=cut
sub add_insertion {
    my ( $self, $seq_name, $position ) = @_;

    return unless exists $self->seqs->{$seq_name};
    my $base_to_replace = substr( $self->seqs->{$seq_name}, $position, 1 );
    my $replacement_base = $INS_BASE_CODE{ uc( $base_to_replace ) };

    substr( $self->seqs->{$seq_name}, $position, 1, $replacement_base);

    return;
}

=head2 truncated_sequence

Create a truncated version of each sequence that covers the target region.

=cut
sub truncated_sequence {
    my ( $self ) = @_;

    my $diff = $self->target_start - $self->genome_start;

    for my $seq_name ( keys %{ $self->seqs } ) {
        my $seq = $self->seqs->{$seq_name};
        my $trun_seq = substr( $seq, $diff - 55, 125 );
        $self->seqs->{ $seq_name . '_trunc' } = $trun_seq;
    }

    return;
}

=head2 grab_genomic_seq

Grab genomic sequence from specified coordinates.

=cut
sub grab_genomic_seq {
    my ( $self, $start, $end ) = @_;

    my $target_string = $self->target_chr . ':' . $start . '-' . $end;
    my @samtools_faidx_cmd = (
        $SAMTOOLS_CMD,
        'faidx',                                  # mpileup command
        $BWA_REF_GENOMES{ lc( $self->species ) }, # reference genome file, faidx-indexed
        $target_string
    );

    $self->log->debug( "samtools faidx command: " . join( ' ', @samtools_faidx_cmd ) );
    my $missing_seq_file = $self->dir->file('missing_sequence.fa')->absolute;
    my $log_file = $self->dir->file( 'samtools_faidx.log' )->absolute;
    run( \@samtools_faidx_cmd,
        '>',  $missing_seq_file->stringify,
        '2>', $log_file->stringify
    ) or die(
            "Failed to run samtools faidx command, see log file: $log_file" );

    my $missing_seq = Bio::SeqIO->new( -fh => $missing_seq_file->openr, -format => 'fasta' );

    return $missing_seq->next_seq->seq;
}

__PACKAGE__->meta->make_immutable;

1;

__END__
