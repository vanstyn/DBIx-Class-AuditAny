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


before 'txn_begin' => sub {
	my $self = shift;
	$_->start_unless_changeset for ($self->all_auditors);
};

# txn_commit
# Note that we're hooking into -before- txn_commit rather than
# -after- which would conceptually make better sense. The reason
# is that we provide for the ability for collectors that store
# their change data within the same schema being tracked, which
# means the stored data will end up being a part of the same 
# transaction, thus hooking into after on the outermost commit
# could cause deep recursion. 
# TODO/FIXME: What about collectors that
# *don't* do this, and an exception occuring within that final
# commit??? It could possibly lead to recording a change that
# didn't actually happen (i.e. was rolled back). I think the way
# to handle this is for the collector to delare if it is storing
# to the tracked schema or not, and handle each case differently
before 'txn_commit' => sub {
	my $self = shift;
	
	# Only finish in the outermost transaction
	if($self->transaction_depth == 1) {
		$_->finish_if_changeset for ($self->all_auditors);
	}
};

around 'txn_rollback' => sub {
	my ($orig, $self, @args) = @_;
	
	my @ret;
	my $want = wantarray;
	try {
		#############################################################
		# ---  Call original - scalar/list/void context agnostic  ---
		@ret = !defined $want ? do { $self->$orig(@args); undef }
			: $want ? $self->$orig(@args)
				: scalar $self->$orig(@args);
		# --- 
		#############################################################
	}
	catch {
		my $err = shift;
		$_->_exception_cleanup($err) for ($self->all_auditors);
		die $err;
	};
	
	# Should never get here because txn_rollback throws an exception
	# per-design. But, we still handle the case for good measure:
	$_->_exception_cleanup('txn_rollback') for ($self->all_auditors);
	
	return $want ? @ret : $ret[0];
};


# insert is the most simple. Always applies to exactly 1 row:
around 'insert' => sub {
	my ($orig, $self, @args) = @_;
	my ($Source, $to_insert) = @args;
	
	# Start new insert operation within each Auditor and get back
	# all the created ChangeContexts from all auditors. The auditors
	# will keep track of their own changes temporarily in a "group":
	my @ChangeContexts = map { 
		$_->_start_current_change_group($Source, 'insert',{
			to_columns => $to_insert 
		})
	} $self->all_auditors;
	
	my @ret;
	my $want = wantarray;
	try {
		#############################################################
		# ---  Call original - scalar/list/void context agnostic  ---
		@ret = !defined $want ? do { $self->$orig(@args); undef }
			: $want ? $self->$orig(@args)
				: scalar $self->$orig(@args);
		# --- 
		#############################################################
	}
	catch {
		my $err = shift;
		$_->_exception_cleanup($err) for ($self->all_auditors);
		die $err;
	};
	
	# Update each ChangeContext with the result data:
	$_->record($ret[0]) for (@ChangeContexts);
	
	# Tell each auditor that we're done and to record the change group
	# into the active changeset:
	$_->_finish_current_change_group for ($self->all_auditors);
	
	return $want ? @ret : $ret[0];
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
	
	my @ret;
	my $want = wantarray;
	try {
		#############################################################
		# ---  Call original - scalar/list/void context agnostic  ---
		@ret = !defined $want ? do { $self->$orig(@args); undef }
			: $want ? $self->$orig(@args)
				: scalar $self->$orig(@args);
		# --- 
		#############################################################
	}
	catch {
		my $err = shift;
		$_->_exception_cleanup($err) for ($self->all_auditors);
		die $err;
	};

	return $want ? @ret : $ret[0];
};


around 'update' => sub {
	my ($orig, $self, @args) = @_;
	my ($Source,$change,$cond) = @args;
	
	# Get the current rows that are going to be updated:
	my $rows = get_raw_source_rows($Source,$cond);
	
	my @change_datam = map {{
		old_columns => $_,
		to_columns => $change,
		condition => $cond
	}} @$rows;
	
	
	
	# (A.) ##########################
	# TODO: find cascade updates here
	#################################
	
	#### IN PROGRESS.....
	##
	### If any of these columns are being changed, we have to also watch the
	### corresponding relationhips for changes (from cascades) during the
	### course of the current database operation. This can be expensive, but
	### we prefer accuracy over speed
	##my $cascade_cols = $self->_get_cascading_rekey_columns($Source);
	##
	### temp: just get all of themfor now
	##my @rels = uniq(map { @{$cascade_cols->{$_}} } keys %$cascade_cols);
	##
	##foreach my $rel (@rels) {
	##	my $rel_rows = get_raw_source_related_rows($Source,$rel,$cond);
	##	#scream_color(CYAN.BOLD,$rel_rows);
	##}
	##
	###scream($Source->source_name,$cascade_cols,\@rels);
	##
	###
	
	
	
	# Start new change operation within each Auditor and get back
	# all the created ChangeContexts from all auditors. The auditors
	# will keep track of their own changes temporarily in a "group":
	my @ChangeContexts = map {
		$_->_start_current_change_group($Source, 'update', @change_datam)
	} $self->all_auditors;
	
	# Do the actual update:
	my @ret;
	my $want = wantarray;
	try {
		#############################################################
		# ---  Call original - scalar/list/void context agnostic  ---
		@ret = !defined $want ? do { $self->$orig(@args); undef }
			: $want ? $self->$orig(@args)
				: scalar $self->$orig(@args);
		# --- 
		#############################################################
	}
	catch {
		my $err = shift;
		$_->_exception_cleanup($err) for ($self->all_auditors);
		die $err;
	};
	
	# Get the primry keys, or all columns if there are none:
	my @pri_cols = $Source->primary_columns;
	@pri_cols = $Source->columns unless (scalar @pri_cols > 0);
	
	# -----
	# Fetch the new values for -each- row, independently. 
	# Build a condition specific to this row and fetch it, 
	# taking into account the change that was just made, and
	# then record the new columns in the ChangeContext:
	foreach my $ChangeContext (@ChangeContexts) {
		my $old = $ChangeContext->{old_columns};
		
		my $new_rows = get_raw_source_rows($Source,{ map {
			$_ => (exists $change->{$_} ? $change->{$_} : $old->{$_})
		} @pri_cols });
		
		# TODO/FIXME: How should we handle it if we got back 
		# something other than exactly one row here?
		die "Unexpected error while trying to read updated row" 
			unless (scalar @$new_rows == 1);
			
		my $new = pop @$new_rows;
		$ChangeContext->record($new);
	}
	# -----
	
	
	# (B.) ##########################
	# TODO: re-fetch rows that were updated via cascade here
	#################################
	
	# Tell each auditor that we're done and to record the change group
	# into the active changeset:
	$_->_finish_current_change_group for ($self->all_auditors);
	
	return $want ? @ret : $ret[0];
};

around 'delete' => sub {
	my ($orig, $self, @args) = @_;
	my ($Source, $cond) = @args;
	
	# Get the current rows that are going to be deleted:
	my $rows = get_raw_source_rows($Source,$cond);
	
	my @change_datam = map {{
		old_columns => $_,
		condition => $cond
	}} @$rows;
	
	###########################
	# TODO: find cascade deletes here
	###########################
	
	
	# Start new change operation within each Auditor and get back
	# all the created ChangeContexts from all auditors. Each auditor
	# will keep track of its own changes temporarily in a "group":
	my @ChangeContexts = map {
		$_->_start_current_change_group($Source, 'delete', @change_datam)
	} $self->all_auditors;
	
	
	# Do the actual deletes:
	my @ret;
	my $want = wantarray;
	try {
		#############################################################
		# ---  Call original - scalar/list/void context agnostic  ---
		@ret = !defined $want ? do { $self->$orig(@args); undef }
			: $want ? $self->$orig(@args)
				: scalar $self->$orig(@args);
		# --- 
		#############################################################
	}
	catch {
		my $err = shift;
		$_->_exception_cleanup($err) for ($self->all_auditors);
		die $err;
	};
	
	
	# TODO: should we go back to the db to make sure the rows are
	# now gone as expected?
	
	$_->record for (@ChangeContexts);
	
	# Tell each auditor that we're done and to record the change group
	# into the active changeset:
	$_->_finish_current_change_group for ($self->all_auditors);
	
	return $want ? @ret : $ret[0];
};



# _get_cascading_rekey_cols: gets a map of column names to relationships. These
# are the relationships that *could* be changed via a cascade when the column (fk)
# is changed.
# TODO: use 'cascade_rekey' attr from DBIx::Class::Shadow 
#  (DBIx::Class::Relationship::Cascade::Rekey) ?
sub _get_cascading_rekey_columns {
	my $self = shift;
	my $Source = shift;
	
	# cache for next time (should I even bother? since if rels are added to the ResultSource
	# later this won't get updated? Is that a bigger risk than the performance boost?)
	$self->_source_cascade_rekey_cols->{$Source->source_name} ||= do {
		my $rels = { map { $_ => $Source->relationship_info($_) } $Source->relationships };
		
		my $cascade_cols = {};
		foreach my $rel (keys %$rels) {
			# Only multi rels apply:
			next unless ($rels->{$rel}{attrs}{accessor} eq 'multi');
			
			# Get all the local columns that effect (i.e. might cascade to) this relationship:
			my @cols = $self->parse_cond_cols_by_alias($rels->{$rel}{cond},'self');
			
			# Add the relationship to list for each column.
			#$cascade_cols->{$_} ||= [] for (@cols); #<-- don't need this
			push @{$cascade_cols->{$_}}, $rel for (@cols);
		}
	
		return $cascade_cols;
	};
	
	return $self->_source_cascade_rekey_rels->{$Source->source_name};
}

has '_source_cascade_rekey_cols', is => 'ro', isa => HashRef, lazy => 1, default => sub {{}};

sub parse_cond_cols_by_alias {
	my $self = shift;
	my $cond = shift;
	my $alias = shift;
	
	# Get the string elements (keys and values)
	# (TODO: deep walk any hahs/array structure)
	my @elements = %$cond;
	
	ref($_) and die "Complex conditions aren't supported yet" for (@elements);
	
	my @cols = map { $_->[1] } # <-- 3. just the column names
		# 2. exclude all but the alias name we want
		grep { $_->[0] eq $alias } 
			# 1. Convert all the element strings into alias/column pairs
			map { [split(/\./,$_,2)] } @elements;
	
	return @cols;
}


sub changeset_do {
	my $self = shift;
	
	# TODO ...
	return $self->txn_do(@_);
}


1;