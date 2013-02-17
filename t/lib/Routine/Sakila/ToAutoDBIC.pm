package # hide from PAUSE
     Routine::Sakila::ToAutoDBIC;
use strict;
use warnings;

use Test::Routine;
with 'Routine::Sakila','Routine::AutoDBIC';

use Test::More; 
use namespace::autoclean;

has 'track_params', is => 'ro', lazy => 1, default => sub {
	my $self = shift;
	my $params = {
		track_all_sources => 1,
		datapoints => [
			(qw(schema schema_ver changeset_ts changeset_elapsed)),
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
	};
	
	return $params;
};


has 'colnames', is => 'ro', isa => 'HashRef[Str]', default => sub {{
	old		=> 'old',
	new		=> 'new',
	column	=> 'column'
}};


test 'Verify Collected Data' => sub {
	my $self = shift;
	my $schema = $self->Auditor->collector->target_schema;
	my $c = $self->colnames;
	
	pass("All is well...");


};

1;