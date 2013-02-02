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


around 'insert' => sub {
	my ($orig, $self, @args) = @_;
	my $Source = $args[0];
	
	## Pre-call code
	
	my ($ret,@ret);
	wantarray ? @ret = $self->$orig(@args) : $ret = $self->$orig(@args);
	
	## Post-call code

	return wantarray ? @ret : $ret;
};

around 'insert_bulk' => sub {
	my ($orig, $self, @args) = @_;
	my $Source = $args[0];
	
	## Pre-call code
	
	my ($ret,@ret);
	wantarray ? @ret = $self->$orig(@args) : $ret = $self->$orig(@args);
	
	## Post-call code

	return wantarray ? @ret : $ret;
};


around 'update' => sub {
	my ($orig, $self, @args) = @_;
	my $Source = $args[0];
	
	## Pre-call code
	
	my ($ret,@ret);
	wantarray ? @ret = $self->$orig(@args) : $ret = $self->$orig(@args);
	
	## Post-call code

	return wantarray ? @ret : $ret;
};

around 'delete' => sub {
	my ($orig, $self, @args) = @_;
	my $Source = $args[0];
	
	## Pre-call code
	
	my ($ret,@ret);
	wantarray ? @ret = $self->$orig(@args) : $ret = $self->$orig(@args);
	
	## Post-call code

	return wantarray ? @ret : $ret;
};


## Need to:
##  1. normalize $ident to be able to get individual rows across all actions
##  2. track rekey in update
##  3. track changes in FK with cascade
##  4. honor wantarray



sub changeset_do {
	my $self = shift;
	
	# TODO ...
	return $self->txn_do(@_);
}


1;