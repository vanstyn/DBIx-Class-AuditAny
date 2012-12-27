# -*- perl -*-

# t/004_auto_dbic_collector.t - test logging changes to the AutoDBIC collector

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
		collector_class => 'DBIx::Class::AuditAny::Collector::AutoDBIC',
		collector_params => {
			sqlite_db => 't/var/audit.db',
		},
		datapoints => [
			(qw(changeset_ts changeset_elapsed)),
			(qw(change_elapsed action source pri_key_value)),
			(qw(column_name old_value new_value)),
		],
		rename_datapoints => {
			changeset_elapsed => 'total_elapsed',
			change_elapsed => 'elapsed',
			pri_key_value => 'row_key',
			new_value => 'new',
			old_value => 'old',
			column_name => 'column',
		},
	),
	"Setup tracker configured to write to auto configured schema"
);

ok( 
	$schema->resultset('Contact')->create({
		first => 'John', 
		last => 'Smith' 
	}),
	"Insert a test row"
);

ok(
	my $Row = $schema->resultset('Contact')->search_rs({ last => 'Smith' })->first,
	"Find the test row"
);

ok(
	$Row->update({ last => 'Doe' }),
	"Update the test row"
);

ok(
	$Row->delete,
	"Delete the test row"
);

ok(
	my $audit_schema = $Auditor->collector->target_schema,
	"Get the active Collector schema object"
);


is(
	$audit_schema->resultset('AuditChangeSet')->count => 3,
	"Expected number of ChangeSets"
);


is(
	$audit_schema->resultset('AuditChangeColumn')->search_rs({
		old => undef,
		new => 'Smith',
		column => 'last',
		'change.action' => 'insert'
	},{
		join => { change => 'changeset' }
	})->count => 1,
	"Expected specific INSERT column change record exists"
);


is(
	$audit_schema->resultset('AuditChangeColumn')->search_rs({
		old => 'Smith',
		new => 'Doe',
		column => 'last',
		'change.action' => 'update',
	},{
		join => { change => 'changeset' }
	})->count => 1,
	"Expected specific UPDATE column change record exists"
);


is(
	$audit_schema->resultset('AuditChangeColumn')->search_rs({
		old => 'Doe',
		new => undef,
		column => 'last',
		'change.action' => 'delete'
	},{
		join => { change => 'changeset' }
	})->count => 1,
	"Expected specific DELETE column change record exists"
);
