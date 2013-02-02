package DBIx::Class::AuditAny::Role::Storage;
use Moo::Role;

# VERSION
# ABSTRACT: Role to apply to tracked DBIx::Class::Storage objects

use strict;
use warnings;
use Try::Tiny;
use DBIx::Class::AuditAny::Util;
use Term::ANSIColor qw(:constants);

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


# insert is the most simple. Always applies to exactly 1 row:
around 'insert' => sub {
	my ($orig, $self, @args) = @_;
	my $Source = $args[0];
	
	scream('[' . (wantarray ? 'LIST' : 'SCAL') . ']' . $Source->source_name . '->insert()');
	
	## Pre-call code
	
	# If we want to capture the data *being* inserted, do it here:
	my $to_insert = $args[1];
	
	## -- Call original --
	my $rv = $self->$orig(@args);
	## -------------------
	
	# $rv should always be a hashref of what (*was*) inserted.
	# Capture it here.
	
	return $rv;
};

around 'insert_bulk' => sub {
	my ($orig, $self, @args) = @_;
	my $Source = $args[0];
	
	scream('[' . (wantarray ? 'LIST' : 'SCAL') . ']' . $Source->source_name . '->insert_bulk()');
	
	## Pre-call code
	
	my ($ret,@ret);
	wantarray ? @ret = $self->$orig(@args) : $ret = $self->$orig(@args);
	
	## Post-call code

	return wantarray ? @ret : $ret;
};


around 'update' => sub {
	my ($orig, $self, @args) = @_;
	my $Source = $args[0];
	
	scream('[' . (wantarray ? 'LIST' : 'SCAL') . ']' . $Source->source_name . '->update()');
	
	# Is this right? from reading the code, it seems that this should be $args[1],
	# but it sure does look like it is in $args[2]...
	my $ident = $args[2];
	scream_color(BOLD.GREEN,$ident);
	
	## Pre-call code
	
	my ($ret,@ret);
	wantarray ? @ret = $self->$orig(@args) : $ret = $self->$orig(@args);
	
	## Post-call code

	return wantarray ? @ret : $ret;
};

around 'delete' => sub {
	my ($orig, $self, @args) = @_;
	my $Source = $args[0];
	
	scream('[' . (wantarray ? 'LIST' : 'SCAL') . ']' . $Source->source_name . '->delete()');
	
	my $ident = $args[1];
	scream_color(BOLD.RED,$ident);
	
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