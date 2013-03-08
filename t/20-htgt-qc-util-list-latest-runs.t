#!/usr/bin/env perl

use strict;
use warnings FATAL => 'all';

use Test::Most;
use Log::Log4perl ':levels';
use HTGT::QC::Config;

Log::Log4perl->easy_init( $DEBUG );

use_ok 'HTGT::QC::Util::ListLatestRuns';

#should we have a custom config? ideally we'd have a temp folder that we can make stuff in.
ok my $llr = HTGT::QC::Util::ListLatestRuns->new( { config => HTGT::QC::Config->new } ), "Constructor succeeds";
isa_ok $llr, 'HTGT::QC::Util::ListLatestRuns', "Object is of correct type";

dies_ok { $llr->get_time_sorted_filenames() } "Empty run ID fails";
dies_ok { $llr->get_time_sorted_filenames("") } "Empty run ID fails";
dies_ok { $llr->get_time_sorted_filenames("non_existent_dir564") } "Invalid dir fails";

ok $llr->get_latest_run_data(), "Get latest run data succeeds";

ok $llr->get_active_runs(), "Get active run succeeds";

done_testing;