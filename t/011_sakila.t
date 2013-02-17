# -*- perl -*-

use strict;
use warnings;
use Test::More;
use Test::Routine::Util;
use lib qw(t/lib);

my $db_file = '/tmp/sakila.db';

unlink $db_file if (-f $db_file);

run_tests(
	"Tracking on the 'Sakila' example db (MySQL)", 
	'Routine::Sakila::ToAutoDBIC' => {
		test_schema_dsn => 'dbi:SQLite:dbname=' . $db_file
	}
);


done_testing;