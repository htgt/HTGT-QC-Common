package HTGT::QC::Action::GenerateReport::Full;

use strict;
use warnings FATAL => 'all';

use Moose;
use MooseX::ClassAttribute;
use List::Util qw( sum );
use YAML::Any;
use CSV::Writer;
use namespace::autoclean;

extends qw( HTGT::QC::Action::GenerateReport );

override command_names => sub {
    'generate-report-full';
};

override abstract => sub {
    'generate full QC results report';
};

class_has init_columns => (
    isa     => 'ArrayRef',
    traits  => ['Array'],
    handles => { init_columns => 'elements' },
    default => sub { [qw( query_well target_id pass score )] }
);

sub execute {
    my ( $self, $opts, $args ) = @_;

    $self->generate_report( $self->analysis_dir, $self->output_file );
}

sub generate_report {
    my ( $self, $analysis_dir, $report_file ) = @_;

    $self->log->info("Generating report");

    my ( @analysis, %primers );

    for my $subdir ( $analysis_dir->children ) {
        for my $yaml_file ( $subdir->children ) {
            my $analysis = YAML::Any::LoadFile($yaml_file);
            push @analysis, $analysis;
            $primers{$_}++ for keys %{ $analysis->{primers} };
        }
    }

    my @PRIMERS = sort keys %primers;

    my $csv = CSV::Writer->new( output => $self->output_file->openw );
    $csv->write(
        $self->init_columns,
        map( {"$_ pass"} @PRIMERS ),
        map( {"$_ critical region score"} @PRIMERS ),
        map( {"$_ target align length"} @PRIMERS ),
        map( {"$_ score"} @PRIMERS ),
        map( {"$_ features"} @PRIMERS )
    );
    for my $analysis (@analysis) {
        $analysis->{score} = sum( map { $analysis->{primers}{$_}{cigar}{score} || 0 } @PRIMERS );
        $csv->write(
            @{$analysis}{ $self->init_columns },
            map( { $analysis->{primers}{$_}{pass} } @PRIMERS ),
            map( { $self->critical_region_score( $analysis->{primers}{$_}{alignment} ) } @PRIMERS ),
            map( { $self->target_align_length( $analysis->{primers}{$_}{cigar} ) } @PRIMERS ),
            map( { $self->align_score( $analysis->{primers}{$_}{cigar} ) } @PRIMERS ),
            map( { join q{,}, @{ $analysis->{primers}{$_}{features} || [] } } @PRIMERS )
        );
    }
}

sub critical_region_score {
    my ( $self, $alignments ) = @_;

    return '' unless $alignments and scalar keys %{$alignments};

    join( q{,}, map { $_->{match_count} . '\\' . $_->{length} } values %{$alignments} );
}

sub target_align_length {
    my ( $self, $cigar ) = @_;

    #make sure we have a valid cigar
    return unless defined $cigar and scalar keys %{$cigar};

    return abs( $cigar->{target_end} - $cigar->{target_start} ) + 1;
}

sub align_score {
    my ( $self, $cigar ) = @_;

    return unless defined $cigar and scalar keys %{$cigar};

    return $cigar->{score};
}

__PACKAGE__->meta->make_immutable;

1;

__END__
