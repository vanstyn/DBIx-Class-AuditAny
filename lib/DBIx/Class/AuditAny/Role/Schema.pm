package DBIx::Class::AuditAny::Role::Schema;
use Moo::Role;

# VERSION
# ABSTRACT: Role to apply to tracked DBIx::Class::Schema objects

use strict;
use warnings;

use Try::Tiny;

requires 'txn_do';

has 'auditors', is => 'ro', lazy => 1, default => sub {[]};
sub all_auditors { @{(shift)->auditors} }
sub auditor_count { scalar (shift)->all_auditors }
sub add_auditor { push @{(shift)->auditors},(shift) } 

around 'txn_do' => sub {
	my ($orig, $self, @args) = @_;
	
	return $self->$orig(@args) unless ($self->auditor_count);
	
	my @ChangeSets = ();
	foreach my $Auditor ($self->all_auditors) {
		push @ChangeSets, $Auditor->start_changeset
			unless ($Auditor->active_changeset);
	};
	
	return $self->$orig(@args) unless (scalar(@ChangeSets) > 0);
	
	my $result;
	try {
		$result = $self->$orig(@args);
		$_->finish for (@ChangeSets);
	}
	catch {
		my $err = shift;
		# Clean up:
		try{$_->AuditObj->clear_changeset} for (@ChangeSets);
		# Re-throw:
		die $err;
	};
	return $result;
};


1;