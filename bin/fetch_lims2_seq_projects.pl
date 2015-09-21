#!/usr/bin/env perl
use strict;
use warnings FATAL => 'all';

use Path::Class;
use HTGT::QC::Util::FileAccessServer;
use Try::Tiny;

# Script to fetch names of sequencing projects
# that are managed by LIMS2 rather than TraceServer (e.g. those submitted for
# external sequencing at EuroFins)

my ($search_string) = @ARGV;

$search_string or die "Project search string must be specified";

my $base_dir = dir( $ENV{'LIMS2_SEQ_FILE_DIR'} ) or die "Could not set sequencing data directory";

my $file_server = HTGT::QC::Util::FileAccessServer->new({
	file_api_url => $ENV{FILE_API_URL}
});

my $dir_paths = $file_server->fileserver_get_json($base_dir->stringify);

foreach my $path (@$dir_paths){
	my $dir = dir($path);
	my $project_name = $dir->basename;
	if($project_name =~/.*$search_string.*/){
	    print "$project_name\n";
	}
}
