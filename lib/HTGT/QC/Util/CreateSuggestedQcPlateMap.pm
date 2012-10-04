package HTGT::QC::Util::CreateSuggestedQcPlateMap;

use strict;
use warnings FATAL => 'all';

use Sub::Exporter -setup => {
    exports => [ qw( create_suggested_plate_map get_sequencing_project_plate_names ) ]
};

use Log::Log4perl qw( :easy );
use HTGT::QC::Util::CigarParser;
use IPC::System::Simple qw( capturex );
use File::Which;
use List::MoreUtils qw( uniq any );
use Array::Compare;

my $SCHEMA;
my $PLATE_OBJECT;

sub create_suggested_plate_map {
    my ($seq_projects, $schema, $plate_object) = @_;

    unless($schema and $schema->isa('DBIx::Class::Schema')){
    	die "Schema $schema must be a DBIx::Class::Schema object";
    }
    unless($plate_object){
    	die "The name of the plate object in the schema must be provided";
    }

    $SCHEMA = $schema;
    $PLATE_OBJECT = $plate_object;

    my $plate_map;

    my $plate_names = get_sequencing_project_plate_names( $seq_projects );
    die "Unable to find sequencing project plate names for: " , join( ',', @{ $seq_projects } )
        if @{ $plate_names } == 0;

    if ( @{ $seq_projects } > 1 ) {
        my @plate_name_lengths = uniq map{ length($_) } @{ $plate_names };

        if ( @plate_name_lengths == 1 ) {
            $plate_map = plate_map_for_same_length_names( $plate_names );
        }
        else {
            $plate_map = plate_map_for_different_length_names( $plate_names );
        }
    }
    elsif ( @{ $seq_projects } == 1 ) {
        return $plate_map ? $plate_map : { map{ $_ => $_ } @{ $plate_names } };
    }

    return $plate_map ? $plate_map : { map{ $_ => '' } @{ $plate_names } };
}

sub get_sequencing_project_plate_names {
    my $seq_projects = shift;
    my @reads;

    my $parser = HTGT::QC::Util::CigarParser->new( strict_mode => 0 );

    my $script_name = 'fetch-seq-reads.sh';
    my $fetch_cmd = File::Which::which( $script_name ) or die "Could not find $script_name";

    foreach my $seq_project ( @{ $seq_projects } ) {
    	## no critic (ProhibitComplexMappings)
        push @reads, map { chomp; $_ } capturex( $fetch_cmd, $seq_project, '--list-only' );
        ## use critic
    }

    my @plate_names;
    foreach my $read ( @reads ) {
        my $results = $parser->parse_query_id( $read );
        push @plate_names, $results->{plate_name};
    }
    my @uniq_plate_names = uniq grep { defined } @plate_names;

    return \@uniq_plate_names;
}

sub plate_map_for_same_length_names {
    my $plate_names = shift;

    my $common_substrings = find_common_grouped_prefixes( $plate_names );

    if ( @{ $common_substrings } == 1 ) {
        my $new_name = create_new_name( $plate_names, $common_substrings->[0] );
        return { map{ $_ => $new_name } @{ $plate_names } };
    }
    elsif ( @{ $common_substrings } > 1 ) {
        my %plate_map;
        foreach my $plate_name ( @{ $plate_names } ) {
            $plate_map{$plate_name} = '';
            foreach my $substring ( @{ $common_substrings } ) {
                $plate_map{$plate_name} = $substring if $plate_name =~ /^$substring/;
            }
        }
        return \%plate_map;
    }

    return;
}

sub plate_map_for_different_length_names {
    my $plate_names = shift;

    my $common_prefix = find_common_prefix( @{ $plate_names } );
    $common_prefix =~ s/_$//;
    if ( any { $_ eq $common_prefix } @{ $plate_names } ){
        return { map{ $_ => $common_prefix } @{ $plate_names } };
    }

    return;
}

sub find_common_grouped_prefixes {
    my $plate_names = shift;
    my $num_plates = @{ $plate_names };

    ## no critic (ProhibitComplexMappings, ProhibitCaptureWithoutTest)
    my @truncated_plate_names = uniq map{ /(.*)_(?:.*)/; $1 } @{ $plate_names };
    ## use critic
    my $num_trun_plate_names = @truncated_plate_names;

    if ( $num_trun_plate_names < $num_plates ) {
        return \@truncated_plate_names;
    }
    else {
        return find_common_grouped_prefixes( \@truncated_plate_names );
    }
}

sub find_common_prefix {
    my $prefix = shift;

    for (@_) {
        chop $prefix while (! /^\Q$prefix\E/);
    }
    return $prefix;
}

sub create_new_name {
    my ( $plate_names, $common_substring ) = @_;

    return $common_substring if $common_substring =~ /^.*_[A-Z1-9]{1}$/;

    my $append = 'A';
    my $new_plate_name = $common_substring . "_$append";
    while ( _new_name_is_invalid( $new_plate_name, $plate_names ) ) {
        $append++;
        return '' if $append eq 'Z';
        $new_plate_name = $common_substring . "_$append";
    }

    return $new_plate_name;
}

sub _new_name_is_invalid {
    my ( $new_plate_name, $current_plate_names ) = @_;

    return 1 if any { $_ =~ /^$new_plate_name/ } @{ $current_plate_names };

    my $plate = $SCHEMA->resultset( $PLATE_OBJECT )->find( { name => $new_plate_name } );
    return 1 if $plate;

    return;
}

1;

__END__
