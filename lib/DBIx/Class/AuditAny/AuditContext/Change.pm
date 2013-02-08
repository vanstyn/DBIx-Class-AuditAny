package DBIx::Class::AuditAny::AuditContext::Change;
use strict;
use warnings;

# VERSION
# ABSTRACT: Default 'Change' context object class for DBIx::Class::AuditAny

use Moose;
use MooseX::AttributeShortcuts; # gives us: is => 'lazy' (see lazy_build)
extends 'DBIx::Class::AuditAny::AuditContext';


use Time::HiRes qw(gettimeofday tv_interval);
use DBIx::Class::AuditAny::Util;

has 'SourceContext', is => 'ro', required => 1;
has 'ChangeSetContext', isa => 'Maybe[Object]', is => 'ro', default => undef;
has 'action', is => 'ro', isa => 'Str', required => 1;

# whether or not to fetch the row from storage again after the action
# to identify changes
has 'new_columns_from_storage', is => 'ro', isa => 'Bool', default => 1;

has 'allowed_actions', is => 'lazy', isa => 'ArrayRef';#, lazy_build => 1;
sub _build_allowed_actions { [qw(insert update delete)] };

has 'executed', is => 'rw', isa => 'Bool', default => 0, init_arg => undef;
has 'recorded', is => 'rw', isa => 'Bool', default => 0, init_arg => undef;

sub class { (shift)->SourceContext->class }
sub ResultSource { (shift)->SourceContext->ResultSource }
sub source { (shift)->SourceContext->source }
sub pri_key_column { (shift)->SourceContext->pri_key_column }
sub pri_key_count { (shift)->SourceContext->pri_key_column }
sub primary_columns { (shift)->SourceContext->primary_columns }
sub get_pri_key_value { (shift)->SourceContext->get_pri_key_value(@_) }


sub _build_tiedContexts { 
	my $self = shift;
	my @Contexts = ( $self->SourceContext );
	unshift @Contexts, $self->ChangeSetContext if ($self->ChangeSetContext);
	return \@Contexts;
}
sub _build_local_datapoint_data { 
	my $self = shift;
	$self->enforce_executed;
	return { map { $_->name => $_->get_value($self) } $self->get_context_datapoints('change') };
}



has 'pri_key_value', is => 'ro', isa => 'Maybe[Str]', lazy => 1, default => sub { 
	my $self = shift;
	$self->enforce_executed;
	
	# TEMP: this is a bridge for converting away from needing Row objects...
	my $merge_cols = { %{$self->old_columns}, %{$self->new_columns} };
	return $self->get_pri_key_value($merge_cols);
	
	#my $Row = $self->Row || $self->origRow;
	#return $self->get_pri_key_value($Row);
};

has 'orig_pri_key_value', is => 'ro', isa => 'Maybe[Str]', lazy => 1, default => sub { 
	my $self = shift;
	
	# TEMP: this is a bridge for converting away from needing Row objects...
	my $merge_cols = { %{$self->new_columns},%{$self->old_columns} };
	return $self->get_pri_key_value($merge_cols);
	
	#return $self->get_pri_key_value($self->origRow);
};

has 'change_ts', is => 'ro', isa => 'DateTime', lazy => 1, default => sub {
	my $self = shift;
	$self->enforce_unexecuted;
	return $self->get_dt;
};

has 'start_timeofday', is => 'ro', default => sub { [gettimeofday] };
has 'change_elapsed', is => 'rw', default => undef;

has 'old_columns', is => 'ro', isa => 'HashRef', lazy => 1, default => sub {{}};
has 'new_columns', is => 'ro', isa => 'HashRef', lazy => 1, default => sub {{}};



#has 'Row', is => 'ro', required => 1;
#
#around 'Row' => sub {
#	my $orig = shift;
#	my $self = shift;
#	return $self->recorded ? $self->newRow : $self->$orig(@_);
#};
#
#
#has 'origRow', is => 'ro', lazy => 1, default => sub {
#	my $self = shift;
#	$self->enforce_unexecuted;
#	return $self->Row->in_storage ? $self->Row->get_from_storage : $self->Row;
#};
#
#has 'newRow', is => 'ro', lazy => 1, default => sub {
#	my $self = shift;
#	$self->enforce_executed;
#	
#	return $self->Row unless (
#		$self->Row->in_storage and
#		$self->new_columns_from_storage and
#		$self->action ne 'select'
#	);
#	return $self->Row->get_from_storage;
#};
#
#has 'old_columns', is => 'ro', isa => 'HashRef', lazy => 1, default => sub {
#	my $self = shift;
#	return {} unless ($self->action ne 'select' && $self->origRow && $self->origRow->in_storage);
#	return { $self->origRow->get_columns };
#};
#
#has 'new_columns', is => 'ro', isa => 'HashRef', lazy => 1, default => sub {
#	my $self = shift;
#	return {} unless ($self->newRow && $self->newRow->in_storage);
#	return { $self->newRow->get_columns };
#};
#
#sub BUILD {
#	my $self = shift;
#	$self->origRow;
#	$self->old_columns;
#}



sub record {
	my $self = shift;
	my $new_columns = shift;
	$self->enforce_unexecuted;
	$self->change_ts;
	$self->change_elapsed(tv_interval($self->start_timeofday));
	$self->executed(1);
	
	%{$self->new_columns} = %$new_columns if (
		ref($new_columns) eq 'HASH' and
		scalar(keys %$new_columns) > 0
	);
	
	#$self->newRow;
	
	$self->recorded(1);
}





has 'action_id_map', is => 'lazy', isa => 'HashRef[Str]';#, lazy_build => 1;
sub _build_action_id_map {{
	insert => 1,
	update => 2,
	delete => 3
}}

sub action_id {
	my $self = shift;
	my $action = $self->action or return undef;
	my $id = $self->action_id_map->{$action} or die "Error looking up action_id";
	return $id;
}


sub enforce_unexecuted {
	my $self = shift;
	die "Error: Audit action already executed!" if ($self->executed);
}

sub enforce_executed {
	my $self = shift;
	die "Error: Audit action not executed yet!" unless ($self->executed);
}


has 'column_changes', is => 'ro', isa => 'HashRef[Object]', lazy => 1, default => sub {
	my $self = shift;
	$self->enforce_executed;
	
	my $old = $self->old_columns;
	my $new = $self->new_columns;
	
	# This logic is duplicated in DbicLink2. Not sure how to avoid it, though,
	# and keep a clean API
	my @changed = ();
	foreach my $col (uniq(keys %$new,keys %$old)) {
		next if (!(defined $new->{$col}) and !(defined $old->{$col}));
		next if (
			defined $new->{$col} and defined $old->{$col} and 
			$new->{$col} eq $old->{$col}
		);
		push @changed, $col;
	}
	
	my %col_context = ();
	my $class = $self->AuditObj->column_context_class;
	foreach my $column (@changed) {
		my $ColumnContext = $class->new(
			AuditObj => $self->AuditObj,
			ChangeContext => $self,
			column_name => $column, 
			old_value => $old->{$column}, 
			new_value => $new->{$column},
		);
		$col_context{$ColumnContext->column_name} = $ColumnContext;
	}
	
	return \%col_context;
};


sub all_column_changes { values %{(shift)->column_changes} }

has 'column_datapoint_values', is => 'ro', isa => 'HashRef', lazy => 1, default => sub {
	my $self = shift;
	#my @Contexts = $self->all_column_changes;
	my @Contexts = values %{$self->column_changes};
	return { map { $_->column_name => $_->local_datapoint_data } @Contexts };
};


has 'column_changes_ascii', is => 'ro', isa => 'Str', lazy => 1, default => sub {
	my $self = shift;
	my $table = $self->column_changes_arr_arr_table;
	return $self->arr_arr_ascii_table($table);
};

has 'column_changes_json', is => 'ro', isa => 'Str', lazy => 1, default => sub {
	my $self = shift;
	my $table = $self->column_changes_arr_arr_table;
	require JSON;
	return JSON::encode_json($table);
};


has 'column_changes_arr_arr_table', is => 'ro', isa => 'ArrayRef',
 lazy => 1, default => sub {
	my $self = shift;
	my @cols = $self->get_context_datapoint_names('column');
	
	my @col_datapoints = values %{$self->column_datapoint_values};
	
	my $table = [\@cols];
	foreach my $col_data (@col_datapoints) {
		my @row = map { $col_data->{$_} || undef } @cols;
		push @$table, \@row;
	}
	
	return $table;
};



sub arr_arr_ascii_table {
	my $self = shift;
	my $table = shift;
	die "Supplied table is not an arrayref" unless (ref($table) eq 'ARRAY');
	
	require Text::TabularDisplay;
	require Text::Wrap;
	
	my $t = Text::TabularDisplay->new;
	
	local $Text::Wrap::columns = 52;
	
	my $header = shift @$table;
	die "Encounted non-arrayref table row" unless (ref($header) eq 'ARRAY');
	
	$t->add(@$header);
	$t->add('');
	
	foreach my $row (@$table) {
		die "Encounted non-arrayref table row" unless (ref($row) eq 'ARRAY');
		$t->add( map { Text::Wrap::wrap('','',$_) } @$row );
	}
	
	return $t->render;
}



1;