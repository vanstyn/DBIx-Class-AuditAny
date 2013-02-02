# -*- perl -*-

# t/005_auto_dbic_collector_defaults.t - test using mostly defaults

use strict;
use warnings;
use Test::More;
use DBICx::TestDatabase 0.04;
use lib qw(t/lib);

plan tests => 12;

use_ok( 'DBIx::Class::AuditAny' );

ok(
	my $schema = DBICx::TestDatabase->new('TestSchema::One'),
	"Initialize Test Database"
);


ok(
	my $Auditor = DBIx::Class::AuditAny->track(
		schema => $schema, 
		track_all_sources => 1,
		collector_class => 'Collector::AutoDBIC',
		collector_params => {
			sqlite_db => 't/var/audit8.db',
		},
	),
	"Setup tracker configured to write to auto configured schema"
);


ok( 
	$schema->resultset('Contact')->create({
		first => 'John', 
		last => 'Smith' 
	}),
	"Insert a test row (1)"
);

ok( 
	$schema->resultset('Contact')->create({
		first => 'Larry', 
		last => 'Smith' 
	}),
	"Insert a test row (2)"
);

ok( 
	$schema->resultset('Contact')->create({
		first => 'Ricky', 
		last => 'Bobby' 
	}),
	"Insert a test row (3)"
);


my $SmithRs = $schema->resultset('Contact')->search_rs({ last => 'Smith' });

is(
	$SmithRs->count => 2,
	"Expected number of Rows with last => 'Smith'"
);


ok(
	$SmithRs->delete,
	"Delete the Smith rows at once"
);



ok(
	my $audit_schema = $Auditor->collector->target_schema,
	"Get the active Collector schema object"
);


is(
	# TODO: this should be 4 once Rs feature is finished:
	$audit_schema->resultset('AuditChangeSet')->count => 5,
	"Expected number of ChangeSets"
);


is(
	$audit_schema->resultset('AuditChangeColumn')->search_rs({
		old_value => undef,
		new_value => 'Smith',
		column_name => 'last',
		'change.action' => 'insert'
	},{
		join => { change => 'changeset' }
	})->count => 2,
	"Expected specific INSERT column change record exists"
);



is(
	$audit_schema->resultset('AuditChangeColumn')->search_rs({
		old_value => 'Smith',
		new_value => undef,
		column_name => 'last',
		'change.action' => 'delete'
	},{
		join => { change => 'changeset' }
	})->count => 2,
	"Expected specific DELETE column change record exists"
);
