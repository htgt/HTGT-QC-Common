package HTGT::QC::Action::Persist::LIMS2SeqReads;

use Moose;
use HTGT::QC::Util::CigarParser;
use Try::Tiny;
use IPC::System::Simple qw( capturex );
use HTGT::QC::Action::FetchSeqReads::TraceArchive;
use namespace::autoclean;

extends qw( HTGT::QC::Action );
with qw( HTGT::QC::Util::LIMS2Client HTGT::QC::Util::SeqReads );

override command_names => sub {
    'persist-lims2-seq-reads'
};

override abstract => sub {
    'persist qc runs seq reads to LIMS2 database'
};

has qc_run_id => (
    is       => 'ro',
    isa      => 'Str',
    traits   => [ 'Getopt' ],
    cmd_flag => 'run-id',
    required => 1
);

has sequencing_projects => (
    isa      => 'ArrayRef[Str]',
    traits   => [ 'Getopt', 'Array' ],
    cmd_flag => 'sequencing-project',
    required => 1,
    handles  => {
        sequencing_projects => 'elements'
    }
);        

has cigar_parser => (
    is         => 'ro',
    isa        => 'HTGT::QC::Util::CigarParser',
    traits     => [ 'NoGetopt' ],
    lazy_build => 1,
    handles    => [ 'parse_query_id' ]
);

has plate_name_map => (
    is         => 'ro',
    isa        => 'HashRef',
    traits     => [ 'Getopt' ],
    cmd_flag   => 'plate-map',
    default    => sub{ {} },
);

has seq_read_sequencing_project => (
    is         => 'ro',
    isa        => 'HashRef',
    lazy_build => 1,
    traits     => [ 'Hash' ],
    handles    => {
        get_sequencing_project_for_read => 'get',
    }
);

has species => (
    is       => 'ro',
    isa      => 'Str',
    traits   => [ 'Getopt' ],
    cmd_flag => 'species',
    required => 1
);

sub _build_seq_read_sequencing_project {
    my $self = shift;
    my %data;

    for my $seq_proj ( $self->sequencing_projects ) {
        map { chomp; $data{$_} = $seq_proj } $self->seq_read_ids;
    }

    return \%data;
}

sub _build_cigar_parser {
    my $self = shift;

    #we don't want to use strict_mode as we still want to fail if we dont get a well or plate,
    #but we want to match all primers or the whole run fails.
    HTGT::QC::Util::CigarParser->new(
        primers   => [ ".*" ], #match all primers
        plate_map => $self->plate_name_map,
    );
}

sub execute {
    my ( $self, $opts, $args ) = @_;
    my %seen;

    for my $seq_read_id ( $self->seq_read_ids ) {
        next if $seen{$seq_read_id}++;
        try{
            $self->_find_or_create_seq_read( $seq_read_id );
        }
        catch {
            #put some useful output in the web viewable log file, too.
            $self->log->debug( "Error processing seq_read: $seq_read_id" ); 
            HTGT::QC::Exception->throw( "Error creating seq_read: $seq_read_id : $_" );
        };
    }

    return;
}

sub _find_or_create_seq_read {
    my ( $self, $seq_read_id ) = @_;

    my $bio_seq = $self->seq_read( $seq_read_id )
        or HTGT::QC::Exception->throw( "Sequence read $seq_read_id not found" );

    $self->log->debug( "Create QCSeqRead: " . $seq_read_id );

    my $parsed = $self->parse_query_id( $seq_read_id );    

    return $self->lims2_client->POST( 'qc_seq_read',
        {
            qc_run_id         => $self->qc_run_id,
            id                => $seq_read_id,
            plate_name        => $parsed->{plate_name},
            well_name         => $parsed->{well_name},
            primer_name       => $parsed->{primer},
            qc_seq_project_id => $self->get_sequencing_project_for_read( $seq_read_id ),
            seq               => $bio_seq->seq,
            description       => $bio_seq->desc || '',
            length            => $bio_seq->length,
            species           => $self->species,
        }
    );
}

1;

__END__
