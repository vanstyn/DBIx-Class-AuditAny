package # hide from PAUSE
     Routine::Sakila;
use strict;
use warnings;

use Test::Routine;
with 'Routine::Base';

use Test::More; 
use namespace::autoclean;

has 'test_schema_class', is => 'ro', default => 'TestSchema::Sakila';

test 'make_db_changes' => { desc => 'Make Database Changes' } => sub {
	my $self = shift;
	my $schema = $self->Schema;
	
	pass("All is well...");
	
	
};

1;