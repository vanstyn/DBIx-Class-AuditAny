# -*- perl -*-

# t/004_auto_dbic_collector.t - test logging changes to the AutoDBIC collector

use strict;
use warnings;
use Test::More;
use Test::Routine::Util;
use lib qw(t/lib);

run_tests(
	'Tracking to custom tables via AutoDBIC collector', 
	'Routine::One::ToAutoDBIC'
);



done_testing;