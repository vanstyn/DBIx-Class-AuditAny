package # hide from PAUSE
     Routine::Base;
use strict;
use warnings;

use Test::Routine;

# This is the *base* routine for:
#  1. initializing a test database
#  2. attaching an auditor to it
#
# Expects to be used with additional Routines having tests that:
#  3. make some db changes
#  4. interrogate those changes in the collector

use Test::More; 
use namespace::autoclean;

use SQL::Translator 0.11016;
use Module::Runtime;

has 'test_schema_class', is => 'ro', isa => 'Str', required => 1;
has 'track_params', is => 'ro', isa => 'HashRef', required => 1;

has 'test_schema_dsn', is => 'ro', isa => 'Str', default => sub{'dbi:SQLite::memory:'};
has 'test_schema_connect', is => 'ro', isa => 'ArrayRef', lazy => 1, default => sub {
	return [ (shift)->test_schema_dsn, '', '', {
		AutoCommit			=> 1,
		on_connect_call	=> 'use_foreign_keys'
	}];
};

sub new_test_schema {
	my $self = shift;
	my $class = shift;
	Module::Runtime::require_module($class);
	my $s = $class->connect(@{$self->test_schema_connect});
	$s->deploy();
	return $s;
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