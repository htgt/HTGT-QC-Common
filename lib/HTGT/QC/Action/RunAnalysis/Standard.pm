package HTGT::QC::Action::RunAnalysis::Standard;

use Moose;
use MooseX::Types::Path::Class;
use HTGT::QC::Util::Analysis;
use Path::Class;
use namespace::autoclean;

extends qw( HTGT::QC::Action::RunAnalysis );

has eng_seqs_dir => (
    is       => 'ro',
    isa      => 'Path::Class::Dir',
    traits   => [ 'Getopt' ],
    cmd_flag => 'eng-seqs',
    coerce   => 1,
    required => 1
);

has output_dir => (
    is       => 'ro',
    isa      => 'Path::Class::Dir',
    traits   => [ 'Getopt' ],
    cmd_flag => 'output-dir',
    coerce   => 1,
    required => 1
);

override command_names => sub {
    'run-analysis'
};

override abstract => sub {
    'analyze alignments of reads to engineered sequences'
};

sub execute {
    my ( $self, $opts, $args ) = @_;

    $self->output_dir->mkpath;

    my $alignments_file = file( $args->[0] );

    my %analyzer_args = (
        alignments_file => $alignments_file,
        sequence_reads  => $self->seq_reads,
        synvec_dir      => $self->eng_seqs_dir,
        output_dir      => $self->output_dir,
        profile         => $self->profile
    );

    my $template_params = $self->template_params;
    if ( $template_params){
        $analyzer_args{template_params} = $template_params;
    }

    my $analyzer = HTGT::QC::Util::Analysis->new(\%analyzer_args);

    $analyzer->analyze_all();
}

__PACKAGE__->meta->make_immutable;

1;

__END__
