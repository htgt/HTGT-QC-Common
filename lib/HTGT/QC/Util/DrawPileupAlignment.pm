package HTGT::QC::Util::DrawPileupAlignment;

=head1 NAME

HTGT::QC::Util::DrawPileupAlignment

=head1 DESCRIPTION

=cut

use Moose;
use MooseX::Types::Path::Class::MoreCoercions qw/AbsFile/;
use namespace::autoclean;

with qw( MooseX::Log::Log4perl );

has [ 'target_start', 'target_end' ] => (
    is       => 'ro',
    isa      => 'Int',
    required => 0,
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

has active_reads => (
    is      => 'rw',
    isa     => 'HashRef',
    default => sub{ {} },
);

has [ 'first_read', 'second_read' ] => (
    is  => 'rw',
    isa => 'Str',
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

    while ( <$fh> ) {
        chomp;
        my ( $chr, $start, $ref, $depth, $reads, $quality ) = split(/\t/);
        if ( $self->current_position == 0 ) {
            $self->calculate_read_positions( $reads );
        }

        my $read_array = $self->split_reads( $reads, $depth );

        # always add current reference base to reference sequence
        $self->seqs->{ref} .= $ref;

        $self->build_sequences( $read_array, $ref, $depth );
        $self->inc_position;
    }

    $self->parse_insertions;

    return $self->seqs;
}

=head2 calculate_read_positions

Work out the positions of the forward and reverse reads in the pileup file.

=cut
sub calculate_read_positions {
    my ( $self, $read ) = @_;

    $read =~ /^\^.(.)/;
    die ( "Can not calculate read positions: $read" ) unless $1;

    if ( $1 =~ /,/ || $1 =~ /[actgn]/ ) {
        $self->first_read('reverse');
        $self->second_read('forward');
    }
    elsif ( $1 =~ /\./ || $1 =~ /[ACTGN]/ ) {
        $self->first_read('forward');
        $self->second_read('reverse');
    }
    else {
        die( "Can not calculate read positions: $read" );
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
sub split_reads {
    my ( $self, $reads_string, $read_depth ) = @_;

    return if $read_depth == 0;

    # deal with indels first, strip them out and store the insertions
    while ( $reads_string =~ /[-+](?<count>[0-9]+)/ ) {
        my $count = $+{count};
        $reads_string =~ s/(?<expr>[-+][0-9]+(?<seq>[A-za-z]{$count}))//;
        my $expr = $+{expr};
        my $seq = $+{seq};
        if ( $expr =~ /^\+/ ) {
            push @{ $self->insertions->{$self->current_position} }, $seq;
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
            # de-activate reads if depth is 1
            $self->active_reads->{forward} = 0;
            $self->active_reads->{reverse} = 0;
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
        $self->seqs->{$self->second_read} .= $self->calculate_base( $read_array->[0], $ref );
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
        $self->seqs->{reverse} .= ' ';
    }
    elsif ( $self->active_reads->{reverse} ) {
        $self->seqs->{reverse} .= $self->calculate_base( $read, $ref );
        $self->seqs->{forward} .= ' ';
    }
    else {
        # in the case where 2 reads do not overlap
        $self->seqs->{$self->first_read}  .= $self->calculate_base( $read, $ref );
        $self->seqs->{$self->second_read} .= ' ';
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
    elsif ( $read =~ /^([A-za-z])$/ ) {
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
    my @insert_positions = sort { $b <=> $a } keys %{ $self->insertions };

    for my $pos ( @insert_positions ) {
        my $inserts = $self->insertions->{$pos};
        if ( scalar( @{ $inserts } ) == 1 ) {
            my $seq = $inserts->[0];
            my $length = length( $seq );
            if ( $seq =~ /^[actgn]+$/ ) {
                $self->add_insertion( 'reverse', $pos, $length, $seq );
                $self->add_insertion( 'forward', $pos, $length );
                $self->add_insertion( 'ref', $pos, $length );
            }
            elsif ( $seq =~ /^[ACTNG]+$/ ) {
                $self->add_insertion( 'forward', $pos, $length, $seq );
                $self->add_insertion( 'reverse', $pos, $length );
                $self->add_insertion( 'ref', $pos, $length );
            }
            else {
                die("Unexpected insert sequences $seq");
            }
        }
        elsif ( scalar( @{ $inserts } ) == 2 ) {
            my $insert_0_length = length( $inserts->[0] );
            my $insert_1_length = length( $inserts->[1] );
            my ( $insert_1_type, $insert_0_type );
            if ( $inserts->[0] =~ /^[actgn]+$/ ) {
                $insert_0_type = 'reverse';
                $insert_1_type = 'forward';
            }
            elsif ( $inserts->[0] =~ /^[ACTGN]+$/ ) {
                $insert_0_type = 'forward';
                $insert_1_type = 'reverse';
            }
            else {
                die("Unexpected insert sequences: " . $inserts->[0] );
            }

            if ( $insert_1_length == $insert_0_length ) {
                $self->add_insertion( $insert_0_type, $pos, $insert_1_length, $inserts->[0] );
                $self->add_insertion( $insert_1_type, $pos, $insert_1_length, $inserts->[1] );
                $self->add_insertion( 'ref', $pos, $insert_1_length );
            }
            elsif ( $insert_0_length > $insert_1_length ) {
                $self->add_insertion( $insert_0_type, $pos, $insert_0_length, $inserts->[0] );
                my $pad_seq = '-' x ( $insert_0_length - $insert_1_length );
                $self->add_insertion( $insert_1_type, $pos, $insert_0_length, $inserts->[1] . $pad_seq );
                $self->add_insertion( 'ref', $pos, $insert_1_length );
            }
            elsif ( $insert_1_length > $insert_0_length ) {
                $self->add_insertion( $insert_1_type, $pos, $insert_1_length, $inserts->[1] );
                my $pad_seq = '-' x ( $insert_1_length - $insert_0_length );
                $self->add_insertion( $insert_0_type, $pos, $insert_1_length, $inserts->[0] . $pad_seq );
                $self->add_insertion( 'ref', $pos, $insert_1_length );
            }
            else {
                die( "Not sure how to deal with insert sequences" );
            }
        }
        else {
            die( "Too many insert sequencs at position $pos: " . scalar( @{ $inserts } ) );
        }
    }
    return;
}

=head2 add_insertion

Push the insert sequence into the named sequence string.

=cut
sub add_insertion {
    my ( $self, $seq_name, $position, $length, $insert_seq ) = @_;
    $insert_seq //= '-' x $length;

    substr( $self->seqs->{$seq_name}, $position, 0, uc( $insert_seq ) );
}

__PACKAGE__->meta->make_immutable;

1;

__END__
