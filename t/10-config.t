#!/usr/bin/env perl

use strict;
use warnings FATAL => 'all';

use FindBin;
use lib "$FindBin::Bin/lib";

use Test::Most;
use Log::Log4perl ':levels';
use MyTest::Util::WriteConfFile;

Log::Log4perl->easy_init( $FATAL );

use_ok 'HTGT::QC::Config';

ok my $conffile = write_conffile(), 'write conffile';

ok my $config = HTGT::QC::Config->new( conffile => $conffile->filename ), 'the constructor succeeds';
isa_ok $config, 'HTGT::QC::Config', '...the object it returns';

ok $config->validate, 'configuration validation succeeds';

ok my @profile_names = $config->profiles, 'profiles() returns a non-empty list';

my $profile_name = $profile_names[0];
ok my $profile = $config->profile( $profile_name ), "get profile $profile_name";
isa_ok $profile, 'HTGT::QC::Config::Profile';

done_testing;
