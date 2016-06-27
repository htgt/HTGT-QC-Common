package HTGT::QC::Action::Misc::AnnotateAlignments;

use Moose;
use MooseX::Types::Path::Class;
use Bio::SeqIO;
use Bio::SeqFeature::Generic;
use YAML::Any;
use namespace::autoclean;

extends qw( HTGT::QC::Action );

override command_names => sub {
    'annotate-alignments'
};

override abstract => sub {
    'add alignment features to a GenBank file'
};

has output_file => (
    is       => 'ro',
    isa      => 'Path::Class::File',
    traits   => [ 'Getopt' ],
    cmd_flag => 'output',
    coerce   => 1,
    required => 1
);

has genbank_file => (
    is       => 'ro',
    isa      => 'Path::Class::File',
    traits   => [ 'Getopt' ],
    cmd_flag => 'genbank-file',
    coerce   => 1,
    required => 1
);

has alignments_file => (
    is       => 'ro',
    isa      => 'Path::Class::File',
    traits   => [ 'Getopt' ],
    cmd_flag => 'alignments',
    coerce   => 1,
    required => 1
);

has query_match => (
    is       => 'ro',
    isa      => 'Str',
    traits   => [ 'Getopt' ],
    cmd_flag => 'match',
    required => 1
);        

sub execute {
    my ( $self, $args, $opts ) = @_;

    my $seq = Bio::SeqIO->new( -fh => $self->genbank_file->openr, -format => 'genbank' )->next_seq;

    my $alignments = YAML::Any::LoadFile( $self->alignments_file );

    my $target_id = $seq->display_id;
    my $match_str = $self->query_match;
    my $rx = qr/$match_str/;    

    for my $a ( @{ $alignments } ) {
        next unless $a->{target_id} eq $target_id
            and $a->{query_id} =~ $rx;
        $a->{query_id} =~ s/^.*\.//;
        my $feature = Bio::SeqFeature::Generic->new(
            -start   => $a->{target_start},
            -end     => $a->{target_end},
            -strand  => $a->{target_strand},
            -primary => 'misc_feature',
            -tag     => { note => "$a->{query_id}" }
        );
        $seq->add_SeqFeature( $feature );
    }

    Bio::SeqIO->new( -fh => $self->output_file->openw, -format => 'genbank' )->write_seq( $seq );    
}

__PACKAGE__->meta->make_immutable;

1;

__END__
