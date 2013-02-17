package # hide from PAUSE
     Routine::Base;
use strict;
use warnings;

use Test::Routine;

# This is the *base* routine for:
#  1. initializing a test database
#  2. attaching an auditor to it
#
# Subsequent Routines should then:
#  3. make some db changes
#  4. interrogate those changes in the collector

use Test::More; 
use namespace::autoclean;

use DBICx::TestDatabase 0.04;

has 'test_schema_class', is => 'ro', isa => 'Str', required => 1;
has 'track_params', is => 'ro', isa => 'HashRef', required => 1;

sub new_test_schema {
	my $self = shift;
	my $schema_class = shift;
	return DBICx::TestDatabase->new($schema_class);
}

has 'Schema' => (
	is => 'ro', isa => 'Object', lazy => 1, 
	clearer => 'reset_Schema',
	default => sub {
		my $self = shift;
		ok(
			my $schema = $self->new_test_schema($self->test_schema_class),
			"Initialize Test Database"
		);
		return $schema;
	}
);

has 'Auditor' => (
	is => 'ro', lazy => 1, 
	clearer => 'reset_Auditor',
	builder => 'build_Auditor'
);

sub build_Auditor {
	my $self = shift;
	
	use_ok( 'DBIx::Class::AuditAny' );
	
	$self->reset_Schema;
	
	my %params = (
		%{$self->track_params},
		schema => $self->Schema
	);
	
	ok(
		my $Auditor = DBIx::Class::AuditAny->track(%params),
		"Initialize Auditor"
	);
	return $Auditor;
}



test 'init_schema_auditor' => { desc => 'Init test schema and auditor' } => sub {
	my $self = shift;
	ok($self->Auditor,"Auditor Initialized");
};


1;