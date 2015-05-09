package DBIx::Class::AuditAny::Role::Schema;
use strict;
use warnings;

# ABSTRACT: Role to apply to tracked DBIx::Class::Schema objects

use Moo::Role;
use MooX::Types::MooseLike::Base qw(:all);


=head1 NAME

DBIx::Class::AuditAny::Role::Schema - Role to apply to tracked DBIx::Class::Schema objects

=head1 DESCRIPTION

This Role is for interfaces only. Its main job is to add the L<DBIx::Class::AuditAny::Role::Storage>
role to the DBIC storage object so the change tracking can occur.

=head1 REQUIRES

=head2 txn_do

Standard method which will be available on all DBIC Schema objects
=cut

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


__END__
=head1 SUPPORT
 
IRC:
 
    Join #rapidapp on irc.perl.org.

=head1 AUTHOR

Henry Van Styn <vanstyn@cpan.org>

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2012 by IntelliTree Solutions llc.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=cut
