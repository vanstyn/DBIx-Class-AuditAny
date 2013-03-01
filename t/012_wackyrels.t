# -*- perl -*-

use strict;
use warnings;
use Test::More;
use Test::Routine::Util;


my $db_file = '/tmp/wacky.db';
my $db_audit_file = '/tmp/wacky-audit.db';

unlink $db_file if (-f $db_file);
unlink $db_audit_file if (-f $db_audit_file);

run_tests(
	"Tracking on the 'WackyRels' example db", 
	'Routine::WackyRels::ToAutoDBIC' => {
		test_schema_dsn => 'dbi:SQLite:dbname=' . $db_file,
		sqlite_db => $db_audit_file
	}
);


done_testing;
