package DBIx::Class::AuditAny::Role::Storage;
use Moo::Role;

# VERSION
# ABSTRACT: Role to apply to tracked DBIx::Class::Storage objects

use strict;
use warnings;

use Try::Tiny;

requires 'txn_do';
requires 'insert';
requires 'update';
requires 'delete';
requires 'insert_bulk';


has 'auditors', is => 'ro', lazy => 1, default => sub {[]};
sub all_auditors { @{(shift)->auditors} }
sub auditor_count { scalar (shift)->all_auditors }
sub add_auditor { push @{(shift)->auditors},(shift) }

around 'insert' => sub { &_tracked_action_call('insert',@_) };
around 'update' => sub { &_tracked_action_call('update',@_) };
around 'delete' => sub { &_tracked_action_call('delete',@_) };




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

sub _tracked_action_call {
	my ($action, $orig, $self, @args) = @_;
	
	my ($source,@a) = @args;
	
	#print STDERR "\n\n\n" . Dumper([$action,(ref $source),@a]) . "\n\n";
	
	#print STDERR "\n      --> " . ref($self) . '->' . $action . "\n\n";
	
	return $self->$orig(@args);
}


sub changeset_do {
	my $self = shift;
	
	# TODO ...
	return $self->txn_do(@_);
}


1;