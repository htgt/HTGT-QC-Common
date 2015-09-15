#!/usr/bin/env perl
use strict;
use warnings FATAL => 'all';

use Path::Class;
use Bio::SeqIO;
use HTGT::QC::Util::FileAccessServer;
use Try::Tiny;

# Script that fetch-seq-reads.sh runs to get reads from sequencing projects
# that are managed by LIMS2 rather than TraceServer (e.g. those submitted for
# external sequencing at EuroFins)

# NB: all output from this script is written to files used by QC system
# Only produce other output if something has gone really wrong

my ($project_name, $list_flag) = @ARGV;

$project_name or die "No sequencing project name provided";

if($list_flag){
	($list_flag eq "--list-only") or die "Script argument $list_flag not supported";
}

my $base_dir = dir( $ENV{'LIMS2_SEQ_FILE_DIR'} ) or die "Could not set sequencing data directory";

my $file_server = HTGT::QC::Util::FileAccessServer->new({
	file_api_url => $ENV{FILE_API_URL}
});

my $project_dir = $base_dir->subdir( $project_name );
my $reads = [];
try{
    $reads = $file_server->fileserver_get_json($project_dir->stringify);
};

if(@$reads){
	foreach my $read_path (@$reads){
		# only use read paths ending .seq
		# or should we look for .seq.clipped?
		my ($path) = ( $read_path =~ /^(.*)\.seq/g );
		next unless $path;

        my $content = $file_server->get_file_content($read_path);
        if($content){
        	if($list_flag){
        		# Parse file in order to get read names
        		# should be the same as the file name but can we rely on this?
        	    my $seq_in = Bio::SeqIO->new( -string => $content, -format => 'fasta' );
                while ( my $bio_seq = $seq_in->next_seq ) {
                    print $bio_seq->id;
                    print "\n";
                }
            }
            else{
            	print $content;
            	print "\n";
            }
        }
    }
}
else{
	# Not found. return silently so fetch-seq-reads.sh can try to find it in TraceServer instead
}

