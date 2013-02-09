package DBIx::Class::AuditAny::Role::Schema;
use strict;
use warnings;

# VERSION
# ABSTRACT: Role to apply to tracked DBIx::Class::Schema objects

use Moo::Role;
use MooX::Types::MooseLike::Base qw(:all);

# This Role is for interfaces only. See the Storage role for the actual
# hooks/logic

use Try::Tiny;
use DBIx::Class::AuditAny::Util;
use DBIx::Class::AuditAny::Role::Storage;

requires 'txn_do';

sub auditors			{ (shift)->storage->auditors(@_) }
sub all_auditors	{ (shift)->storage->all_auditors(@_) }
sub auditor_count	{ (shift)->storage->auditor_count(@_) }
sub add_auditor		{ (shift)->storage->add_auditor(@_) }
sub changeset_do	{ (shift)->storage->changeset_do(@_) }

sub BUILD {}
after BUILD => sub {
	my $self = shift;
	# Just for good measure, not usally called because the role is applied
	# after the fact (see AuditAny.pm)
	$self->_apply_storage_role;
};

sub _apply_storage_role {
	my $self = shift;
	# Apply the role to the Storage object:
	Moo::Role->apply_roles_to_object($self->storage,'DBIx::Class::AuditAny::Role::Storage')
		unless try{$self->storage->does('DBIx::Class::AuditAny::Role::Storage')};
}


1;