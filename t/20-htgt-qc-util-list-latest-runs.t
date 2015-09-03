#!/usr/bin/env perl

use strict;
use warnings FATAL => 'all';

#so we can import WriteConfFile
use FindBin;
use lib "$FindBin::Bin/lib";

use Test::Most;
use Log::Log4perl ':levels';

use MyTest::Util::WriteConfFile;
use HTGT::QC::Config;
use Config::Tiny;

Log::Log4perl->easy_init( $DEBUG );

use_ok 'HTGT::QC::Util::ListLatestRuns';

{
    my $conf_file = write_conffile();
    my $config = HTGT::QC::Config->new( conffile => $conf_file->filename );

    my $file_api_url = $ENV{FILE_API_URL}; # This sets it in HTGT environment
    unless($file_api_url){
    	# or this way in LIMS2
        $ENV{ LIMS2_URL_CONFIG }
        or die "LIMS2_URL_CONFIG environment variable not set";
        my $conf = Config::Tiny->read( $ENV{ LIMS2_URL_CONFIG } );
        $file_api_url = $conf->{_}->{lustre_server_url}
        or die "lustre_server_url not found in LIMS2_URL_CONFIG file ".$ENV{ LIMS2_URL_CONFIG };
    }

    ok my $llr = HTGT::QC::Util::ListLatestRuns->new( { config => $config, file_api_url =>  $file_api_url } ), "Constructor succeeds";
    isa_ok $llr, 'HTGT::QC::Util::ListLatestRuns', "Object is of correct type: ";

    dies_ok { $llr->get_time_sorted_filenames() } "Empty run ID fails";
    dies_ok { $llr->get_time_sorted_filenames( "" ) } "Empty run ID fails";
    dies_ok { $llr->get_time_sorted_filenames( "non_existent_dir564" ) } "Invalid dir fails";

    isa_ok $llr->get_latest_run_data, ref [], "Get latest run data return value is correct: ";
    isa_ok $llr->get_active_runs, ref [], "Get active runs return value is correct: ";
}

done_testing;
