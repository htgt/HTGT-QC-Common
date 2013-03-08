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

Log::Log4perl->easy_init( $DEBUG );

use_ok 'HTGT::QC::Util::ListLatestRuns';

{
    my $conf_file = write_conffile();
    my $config = HTGT::QC::Config->new( conffile => $conf_file->filename );

    ok my $llr = HTGT::QC::Util::ListLatestRuns->new( { config => $config } ), "Constructor succeeds";
    isa_ok $llr, 'HTGT::QC::Util::ListLatestRuns', "Object is of correct type: ";

    dies_ok { $llr->get_time_sorted_filenames() } "Empty run ID fails";
    dies_ok { $llr->get_time_sorted_filenames( "" ) } "Empty run ID fails";
    dies_ok { $llr->get_time_sorted_filenames( "non_existent_dir564" ) } "Invalid dir fails";

    isa_ok $llr->get_latest_run_data, ref [], "Get latest run data return value is correct: ";
    isa_ok $llr->get_active_runs, ref [], "Get active runs return value is correct: ";
}

done_testing;
