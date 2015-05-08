# -*- perl -*-

use strict;
use warnings;
use Test::More;
use DBICx::TestDatabase 0.04;
use lib qw(t/lib);

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
	$SmithRs->update({ last => 'Smyth' }),
	"Update the Smith rows at once"
);

# Get the newly changed Rs (was sort of surprised this didn't happen automatically)
$SmithRs = $schema->resultset('Contact')->search_rs({ last => 'Smyth' });

ok(
	$SmithRs->delete,
	"Delete the Smith rows at once"
);


# insert_bulk not yet
SKIP: {
	ok(
		# Force VOID context (needed to test Storgae::insert_bulk codepath)
		do { $schema->resultset('Contact')->populate([
			[qw(first last)],
			[qw(John Stossel)],
			[qw(Richard Dawkins)],
		]); 1; },
		"Insert several rows at once with populate (arrayref/arrayref syntax)"
	);

	ok(
		# Force VOID context (needed to test Storgae::insert_bulk codepath)
		do { $schema->resultset('Contact')->populate([
			{ first => 'Christopher',	last => 'Hitchens' },
			{ first => 'Sam', 			last => 'Harris' },
		]); 1; },
		"Insert several rows at once with populate (arrayref/hashref syntax)"
	);
};


#####################


ok(
	my $audit_schema = $Auditor->collector->target_schema,
	"Get the active Collector schema object"
);


is(
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
		new_value => 'Smyth',
		column_name => 'last',
		'change.action' => 'update'
	},{
		join => { change => 'changeset' }
	})->count => 2,
	"Expected specific UPDATE column change record exists"
);


is(
	$audit_schema->resultset('AuditChangeColumn')->search_rs({
		old_value => 'Smyth',
		new_value => undef,
		column_name => 'last',
		'change.action' => 'delete'
	},{
		join => { change => 'changeset' }
	})->count => 2,
	"Expected specific DELETE column change record exists"
);



my $expected_change_rows = [
  {
    change_id => 1,
    column_name => "first",
    id => 1,
    new_value => "John",
    old_value => undef
  },
  {
    change_id => 1,
    column_name => "last",
    id => 2,
    new_value => "Smith",
    old_value => undef
  },
  {
    change_id => 1,
    column_name => "id",
    id => 3,
    new_value => 1,
    old_value => undef
  },
  {
    change_id => 2,
    column_name => "first",
    id => 4,
    new_value => "Larry",
    old_value => undef
  },
  {
    change_id => 2,
    column_name => "last",
    id => 5,
    new_value => "Smith",
    old_value => undef
  },
  {
    change_id => 2,
    column_name => "id",
    id => 6,
    new_value => 2,
    old_value => undef
  },
  {
    change_id => 3,
    column_name => "first",
    id => 7,
    new_value => "Ricky",
    old_value => undef
  },
  {
    change_id => 3,
    column_name => "last",
    id => 8,
    new_value => "Bobby",
    old_value => undef
  },
  {
    change_id => 3,
    column_name => "id",
    id => 9,
    new_value => 3,
    old_value => undef
  },
  {
    change_id => 4,
    column_name => "last",
    id => 10,
    new_value => "Smyth",
    old_value => "Smith"
  },
  {
    change_id => 5,
    column_name => "last",
    id => 11,
    new_value => "Smyth",
    old_value => "Smith"
  },
  {
    change_id => 6,
    column_name => "first",
    id => 12,
    new_value => undef,
    old_value => "John"
  },
  {
    change_id => 6,
    column_name => "last",
    id => 13,
    new_value => undef,
    old_value => "Smyth"
  },
  {
    change_id => 6,
    column_name => "id",
    id => 14,
    new_value => undef,
    old_value => 1
  },
  {
    change_id => 7,
    column_name => "first",
    id => 15,
    new_value => undef,
    old_value => "Larry"
  },
  {
    change_id => 7,
    column_name => "last",
    id => 16,
    new_value => undef,
    old_value => "Smyth"
  },
  {
    change_id => 7,
    column_name => "id",
    id => 17,
    new_value => undef,
    old_value => 2
  }
];

my $actual_change_rows = [ $audit_schema->resultset('AuditChangeColumn')->search_rs(undef,{
	result_class => 'DBIx::Class::ResultClass::HashRefInflator'
})->all ];

is_deeply(
	$actual_change_rows, $expected_change_rows,
	"Expected full contents of AuditChangeColumn table"
);


done_testing;
