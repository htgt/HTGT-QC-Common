#!/usr/bin/env perl
use strict;
use warnings FATAL => 'all';

use Path::Class;
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
	($list_flag eq "--list_only") or die "Script argument $list_flag not supported";
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
		my ($path) = ( $read_path =~ /^(.*)\.seq/g );
		next unless $path;

		my $read_file = file($path);
		my $read_name = $read_file->basename;
		if($list_flag){
            print "$read_name\n";
        }
        else{
        	# Fetch seq file and print content
        	my $sequence = $file_server->get_file_content($read_path);
        	print ">$read_name\n";
        	print "$sequence\n";
        }
    }
}
else{
	# Not found. return silently so fetch-seq-reads.sh can try to find it in TraceServer instead
}

