# -*- perl -*-

# t/006_auto_dbic_collector_all_datapoints.t - test using all built-in datapoints

use strict;
use warnings;
use Test::More;
use DBICx::TestDatabase 0.04;
use lib qw(t/lib);

plan tests => 12;

use DBIx::Class::AuditAny::Util::BuiltinDatapoints;

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
			sqlite_db => 't/var/audit3.db',
		},
		datapoints => [ map { $_->{name} } DBIx::Class::AuditAny::Util::BuiltinDatapoints->all_configs ] 
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
		old_value => undef,
		new_value => 'Smith',
		column_name => 'last',
		'change.action' => 'insert'
	},{
		join => { change => 'changeset' }
	})->count => 1,
	"Expected specific INSERT column change record exists"
);


is(
	$audit_schema->resultset('AuditChangeColumn')->search_rs({
		old_value => 'Smith',
		new_value => 'Doe',
		column_name => 'last',
		'change.action' => 'update',
	},{
		join => { change => 'changeset' }
	})->count => 1,
	"Expected specific UPDATE column change record exists"
);


is(
	$audit_schema->resultset('AuditChangeColumn')->search_rs({
		old_value => 'Doe',
		new_value => undef,
		column_name => 'last',
		'change.action' => 'delete'
	},{
		join => { change => 'changeset' }
	})->count => 1,
	"Expected specific DELETE column change record exists"
);
