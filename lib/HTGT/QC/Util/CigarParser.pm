package HTGT::QC::Util::CigarParser;

use Moose;
use MooseX::ClassAttribute;
use Const::Fast;
use Data::Dump 'pp';
use HTGT::QC::Exception;
use Path::Class;
use Iterator::Simple;
use Scalar::Util;
use IO::Handle;
use namespace::autoclean;

with qw( MooseX::Log::Log4perl );

## no critic (RegularExpressions::ProhibitComplexRegexes)
const my $CIGAR_RX => qr(
    ^cigar:
    \s+
    (\S+)                 # query_id
    \s+
    (\d+)                 # query_start
    \s+
    (\d+)                 # query_end
    \s+
    ([+-])                # query_strand
    \s+
    (\S+)                 # target_id
    \s+
    (\d+)                 # target_start
    \s+
    (\d+)                 # target_end
    \s+
    ([+-])                # target_strand
    \s+
    (\d+)                 # score
    \s+
    (.+)                  # operator/length pairs
    $
)x;
## use critic

const my $OP_STR_RX => qr(
   \s*
   ([DIM])     # operation
   \s+
   (\d+)       # length
)x;

const my @CIGAR_FIELDS => qw(
    query_id
    query_start
    query_end
    query_strand
    target_id
    target_start
    target_end
    target_strand
    score
    op_str
);

has strict_mode => (
    is      => 'ro',
    isa     => 'Bool',
    default => 1
);

has primer_names => (
    isa      => 'ArrayRef[Str]',
    init_arg => 'primers',
    traits   => [ 'Array' ],
    handles  => {
        primer_names => 'elements'
    },
    default => sub { [] }
);

has plate_name_map => (
    isa       => 'HashRef',
    init_arg  => 'plate_map',
    traits    => [ 'Hash' ],
    handles   => {
        has_canonical_name => 'exists',
        get_canonical_name => 'get'
    },
    default   => sub { {} }
);

sub canonical_plate_name {
    my ( $self, $plate_name ) = @_;

    if ( $self->has_canonical_name( $plate_name ) ) {
        return $self->get_canonical_name( $plate_name );
    }

    return $plate_name;
}

has query_primer_rx => (
    is         => 'ro',
    isa        => 'Regexp',
    init_arg   => undef,
    lazy_build => 1,
);

sub _build_query_primer_rx {
    my $self = shift;

    my @primer_names = $self->primer_names;
    if ( @primer_names == 0 ) {
        if ( $self->strict_mode ) {
            HTGT::QC::Exception->throw( 'primers must be set in strict mode' );
        }
        else {
            push @primer_names, '.*'; # match anything
        }
    }

    my $primer_match = join '|', @primer_names;

    return qr/^(.+)\.(?:[a-z]\d)k\d*[a-z]?($primer_match)[a-z]?$/;
}

sub parse_query_id {
    my ( $self, $query_id ) = @_;

    # XXX this is a hack, do we need something more general?
    $query_id =~ s/_20mer$//;

    my ( $well, $primer ) = $query_id =~ $self->query_primer_rx;

    $self->log->trace( sprintf "parse_query_id: '%s' => well: %s, primer: %s",
                       $query_id, (defined $well ? $well : '<undef>'), (defined $primer ? $primer : '<undef>')
                   );

    if ( $self->strict_mode and ( not defined $well or not defined $primer ) ) {
        HTGT::QC::Exception->throw( "Failed to parse query_id: $query_id" );
    }

    my %res = ( primer => $primer );

    if ( $well ) {
        $res{plate_name} = substr( $well, 0, -3 );
        $res{well_name}  = uc substr( $well, -3 );
        if ( my $canon_name = $self->canonical_plate_name( $res{plate_name} ) ) {
            $res{plate_name} = $canon_name;
        }
    }

    return \%res;
}

sub parse_cigar {
    my ( $self, $cigar_str ) = @_;

    chomp( $cigar_str );

    $self->log->trace( "Parsing CIGAR string: '$cigar_str'" );

    my %parsed;

    @parsed{ @CIGAR_FIELDS } = $cigar_str =~ $CIGAR_RX
        or HTGT::QC::Exception->throw( "failed to parse CIGAR '$cigar_str'" );

    my @op_pairs = $parsed{op_str} =~ m/$OP_STR_RX/g;

    my @operations;
    while ( @op_pairs ) {
        my ( $op, $length ) = splice @op_pairs, 0, 2;
        push @operations, [ $op, $length ];
    }

    $parsed{operations} = \@operations;

    my $parsed_query_id = $self->parse_query_id( $parsed{query_id} );

    $parsed{query_well}   = join '', @{$parsed_query_id}{ qw( plate_name well_name ) };
    $parsed{query_primer} = $parsed_query_id->{primer};
    $parsed{raw}          = $cigar_str;
    $parsed{length}       = abs( $parsed{target_end} - $parsed{target_start} );

    $self->log->trace( sub { 'Parsed cigar: ' . pp \%parsed } );

    return \%parsed;
}

sub parse_files {
    my $self = shift;

    my @parsed;
    my $it = $self->file_iterator( @_ );
    while ( defined( my $v = $it->next ) ) {
        push @parsed, $v;
    }

    return \@parsed;
}

sub file_iterator {
    my $self = shift;

    return Iterator::Simple::ichain map { $self->_single_file_iterator( $_ ) } @_;
}

sub _single_file_iterator {
    my ( $self, $filename ) = @_;

    my ( $fh, $done_init );

    return Iterator::Simple::iterator {
        unless ( $done_init ) {
            $self->log->debug( "Reading CIGARs from $filename" );
            $fh = $self->input_fh( $filename );
            $done_init = 1;
        }
        while ( ! $fh->eof ) {
            defined( my $line = $fh->getline )
                or next;
            next unless $line =~ m/^cigar:/;
            return $self->parse_cigar( $line );
        }
        $fh->close;
        return;
    };
}

## no critic ( ControlStructures::ProhibitCascadingIfElse )
sub input_fh {
    my ( $self, $input ) = @_;

    my $ifh;
    if ( ! ref $input ) {
        $self->log->debug( "Parsing exonerate output from $input" );
        $ifh = file( $input )->openr;
    }
    elsif ( $input->isa( 'Path::Class::File' ) ) {
        $self->log->debug( "Parsing exonerate output from $input" );
        $ifh = $input->openr;
    }
    elsif ( $input->isa( 'IO::Handle' ) ) {
        $self->log->debug( "Parsing exonerate output from IO::Handle" );
        $ifh = $input;
    }
    elsif ( Scalar::Util::openhandle( $input ) ) {
        $self->log->debug( "Parsing exonerate output from open filehandle" );
        $ifh = IO::Handle->new_from_fd( $input, 'r' )
    }
    else {
        HTGT::QC::Exception->throw( "Don't know how to read from a " . ref $input );
    }

    return $ifh;
}
## use critic

1;

__END__
