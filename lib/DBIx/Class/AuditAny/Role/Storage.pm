package DBIx::Class::AuditAny::Role::Storage;
use strict;
use warnings;

# VERSION
# ABSTRACT: Role to apply to tracked DBIx::Class::Storage objects

use Moo::Role;
use MooX::Types::MooseLike::Base qw(:all);

## TODO:
##  1. track rekey in update
##  2. track changes in FK with cascade


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
	my ($Source, $to_insert) = @args;
	
	#############################################################
	# ---  Call original - scalar/list/void context agnostic  ---
	my @ret = !defined wantarray ? do { $self->$orig(@args); undef }
		: wantarray ? $self->$orig(@args)
			: scalar $self->$orig(@args);
	# --- 
	#############################################################
	
	# Send the insert to each attached Auditor:
	$_->_record_inserts($Source,$ret[0]) for ($self->all_auditors);
	
	return wantarray ? @ret : $ret[0];
};


### TODO: ###
# insert_bulk is a tricky case. It exists for the purpose of performance,
# and skips reading back in the inserted row(s). BUT, we need to read back
# in the inserted row, and we have no safe way of doing that with a bulk
# insert (auto-generated auti-inc keys, etc). DBIC was already designed with
# with this understanding, and so insert_bulk is already only called when 
# no result is needed/expected back: DBIx::Class::ResultSet->populate() called
# in *void* context. 
#
# Based on this fact, I think that the only rational way to be able to
# Audit the inserted rows is to override and convert any calls to insert_bulk()
# into calls to regular calls to insert(). Interferring with the original
# flow/operation is certainly not ideal, but I don't see any alternative.
around 'insert_bulk' => sub {
	my ($orig, $self, @args) = @_;
	my ($Source, $cols, $data) = @args;
	
	#
	# TODO ....
	#
	
	#############################################################
	# ---  Call original - scalar/list/void context agnostic  ---
	my @ret = !defined wantarray ? do { $self->$orig(@args); undef }
		: wantarray ? $self->$orig(@args)
			: scalar $self->$orig(@args);
	# --- 
	#############################################################

	return wantarray ? @ret : $ret[0];
};




around 'update' => sub {
	my ($orig, $self, @args) = @_;
	my ($Source,$change,$cond) = @args;
	
	# 1. Get the current rows that are going to be updated:
	my $rows = $self->_get_raw_rows($Source,$cond);
	
	# (A.) ##########################
	# TODO: find cascade updates here
	#################################
	
	# 2. Do the actual update:
	#############################################################
	# ---  Call original - scalar/list/void context agnostic  ---
	my @ret = !defined wantarray ? do { $self->$orig(@args); undef }
		: wantarray ? $self->$orig(@args)
			: scalar $self->$orig(@args);
	# --- 
	#############################################################
	
	# Get the primry keys, or all columns if there are none:
	my @pri_cols = $Source->primary_columns;
	@pri_cols = $Source->columns unless (scalar @pri_cols > 0);
	
	# -----
	# 3. Fetch the new values for -each- row, independently. 
	# Build a condition specific to this row and fetch it, 
	# taking into account the change that was just made:
	my @updates = ();
	foreach my $old (@$rows) {
		my $new_rows = $self->_get_raw_rows($Source,{ map {
			$_ => (exists $change->{$_} ? $change->{$_} : $old->{$_})
		} @pri_cols });
		
		# TODO/FIXME: How should we handle it if we got back 
		# something other than exactly one row here?
		die "Unexpected error while trying to read updated row" 
			unless (scalar @$new_rows == 1);
			
		my $new = pop @$new_rows;
		push @updates, { 
			old => $old, 
			new => $new 
		};
	}
	# -----
	
	# (B.) ##########################
	# TODO: re-fetch rows that were updated via cascade here
	#################################
	
	# Send the updates to each attached Auditor:
	$_->_record_updates($Source,@updates) for ($self->all_auditors);
	
	return wantarray ? @ret : $ret[0];
};

around 'delete' => sub {
	my ($orig, $self, @args) = @_;
	my ($Source, $cond) = @args;
	
	# Get the current rows that are going to be deleted:
	my $rows = $self->_get_raw_rows($Source,$cond);
	
	###########################
	# TODO: find cascade deletes here
	###########################
	
	# Do the actual deletes:
	#############################################################
	# ---  Call original - scalar/list/void context agnostic  ---
	my @ret = !defined wantarray ? do { $self->$orig(@args); undef }
		: wantarray ? $self->$orig(@args)
			: scalar $self->$orig(@args);
	# --- 
	#############################################################
	
	
	# TODO: should we go back to the db to make sure the rows are
	# now gone as expected?
	
	# Send the deletes to each attached Auditor:
	$_->_record_deletes($Source,@$rows) for ($self->all_auditors);
	
	return wantarray ? @ret : $ret[0];
};

# (logic adapted from DBIx::Class::Storage::DBI::insert)
sub _get_raw_rows {
	my $self = shift;
	my $Source = shift;
	my $cond = shift;

	my @rows = ();
	my @cols = $Source->columns;
	
	my $cur = DBIx::Class::ResultSet->new($Source, {
		where => $cond,
		select => \@cols,
	})->cursor;
	
	while(my @data = $cur->next) {
		my %returned_cols = ();
		@returned_cols{@cols} = @data;
		push @rows, \%returned_cols;
	}

	return \@rows;
}


sub changeset_do {
	my $self = shift;
	
	# TODO ...
	return $self->txn_do(@_);
}


1;