# -*- perl -*-

use strict;
use warnings;
use Test::More;
use Test::Routine::Util;
use lib qw(t/lib);

run_tests(
	"Tracking on the 'Sakila' example db (MySQL)", 
	'Routine::Sakila::ToAutoDBIC'
);



done_testing;