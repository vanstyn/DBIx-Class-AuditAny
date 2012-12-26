# -*- perl -*-

# t/002_record_custom_tables.t - test logging changes to existing/custom tables

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

my $user_id = 42;
my $client_ip = '1.2.3.4';

ok(
	DBIx::Class::AuditAny->track(
		schema => $schema, 
		track_all_sources => 1,
		collector_class => 'DBIx::Class::AuditAny::Collector::DBIC',
		collector_params => {
			target_source => 'AuditChangeSet',
			change_data_rel => 'audit_changes',
			column_data_rel => 'audit_change_columns',
		},
		datapoints => [
			(qw(changeset_ts changeset_elapsed)),
			(qw(change_elapsed action source pri_key_value)),
			(qw(column_name old_value new_value)),
		],
		datapoint_configs => [
			{
				name	=> 'client_ip',
				context => 'set',
				method => sub { $client_ip }
			},
			{
				name	=> 'user_id',
				context => 'set',
				method => sub { $user_id }
			}
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
	"Setup tracker configured to write custom datapoints to custom tables"
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

$client_ip = '4.5.6.7';

ok(
	$Row->delete,
	"Delete the test row"
);

is(
	$schema->resultset('AuditChangeSet')->count => 3,
	"Expected number of ChangeSets"
);

is(
	$schema->resultset('AuditChangeColumn')->search_rs({
		old => undef,
		new => 'Smith',
		column => 'last',
		'change.action' => 'insert',
		'changeset.user_id' => $user_id
	},{
		join => { change => 'changeset' }
	})->count => 1,
	"Expected specific INSERT column change record exists"
);


is(
	$schema->resultset('AuditChangeColumn')->search_rs({
		old => 'Smith',
		new => 'Doe',
		column => 'last',
		'change.action' => 'update',
		'changeset.user_id' => $user_id
	},{
		join => { change => 'changeset' }
	})->count => 1,
	"Expected specific UPDATE column change record exists"
);


is(
	$schema->resultset('AuditChangeColumn')->search_rs({
		old => 'Doe',
		new => undef,
		column => 'last',
		'change.action' => 'delete',
		'changeset.client_ip' => $client_ip
	},{
		join => { change => 'changeset' }
	})->count => 1,
	"Expected specific DELETE column change record exists"
);

is(
	$schema->resultset('AuditChange')->search_rs({
		'changeset.client_ip' => $client_ip
	},{
		join => 'changeset'
	})->first->audit_change_columns->count => 3,
	"Expected number of specific column changes via rel accessor"
);
