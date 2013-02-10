package DBIx::Class::AuditAny;
use strict;
use warnings;

# VERSION
# ABSTRACT: Flexible change tracking framework for DBIx::Class

use Moo;
use MooX::Types::MooseLike::Base 0.19 qw(:all);

#use Moose;
#use MooseX::Types::Moose qw(HashRef ArrayRef Str Bool Maybe Object);

use Class::MOP;
use Class::MOP::Class;
use DateTime;
use DBIx::Class::AuditAny::Util;
use DBIx::Class::AuditAny::Util::BuiltinDatapoints;
use DBIx::Class::AuditAny::Role::Schema;

has 'time_zone', is => 'ro', isa => Str, default => sub{'local'};
sub get_dt { DateTime->now( time_zone => (shift)->time_zone ) }

has 'schema', is => 'ro', required => 1, isa => InstanceOf['DBIx::Class::Schema']; #<--- This won't go back to Moose
has 'track_immutable', is => 'ro', isa => Bool, default => sub{0};
has 'track_actions', is => 'ro', isa => ArrayRef, default => sub { [qw(insert update delete)] };
has 'allow_multiple_auditors', is => 'ro', isa => Bool, default => sub{0};

has 'source_context_class', is => 'ro', default => sub{'AuditContext::Source'};
has 'change_context_class', is => 'ro', default => sub{'AuditContext::Change'};
has 'changeset_context_class', is => 'ro', default => sub{'AuditContext::ChangeSet'};
has 'column_context_class', is => 'ro', default => sub{'AuditContext::Column'};
has 'default_datapoint_class', is => 'ro', default => sub{'DataPoint'};
has 'collector_class', is => 'ro', isa => Str;

around $_ => sub { 
	my $orig = shift; my $self = shift; 
	resolve_localclass $self->$orig(@_);
} for qw(
 source_context_class change_context_class
 changeset_context_class column_context_class
 default_datapoint_class collector_class
);

has 'collector_params', is => 'ro', isa => HashRef, default => sub {{}};
has 'primary_key_separator', is => 'ro', isa => Str, default => sub{'|~|'};
has 'datapoint_configs', is => 'ro', isa => ArrayRef[HashRef], default => sub {[]};
has 'auto_include_user_defined_datapoints', is => 'ro', isa => Bool, default => sub{1};
has 'rename_datapoints', is => 'ro', isa => Maybe[HashRef[Str]], default => sub{undef};
has 'disable_datapoints', is => 'ro', isa => ArrayRef, default => sub {[]};
has 'record_empty_changes', is => 'ro', isa => Bool, default => sub{0};

has 'datapoints', is => 'ro', isa => ArrayRef[Str], 
 default => sub{[qw(
  change_ts
  action
  source
  pri_key_value
  column_name
  old_value
  new_value
)]};

has 'collector', is => 'ro', lazy => 1, default => sub {
	my $self = shift;
	return ($self->collector_class)->new(
		%{$self->collector_params},
		AuditObj => $self
	);
};

# Any sources within the tracked schema that the collector is writing to; these
# sources are not allowed to be tracked because it would create infinite recursion:
has 'log_sources', is => 'ro', isa => ArrayRef[Str], lazy => 1, init_arg => undef, default => sub {
	my $self = shift;
	return $self->collector->writes_bound_schema_sources;
};

has 'tracked_action_functions', is => 'ro', isa => HashRef, default => sub {{}};
has 'tracked_sources', is => 'ro', isa => HashRef[Str], default => sub {{}};
has 'calling_action_function', is => 'ro', isa => HashRef[Bool], default => sub {{}};
has 'active_changeset', is => 'rw', isa => Maybe[Object], default => sub{undef};
has 'auto_finish', is => 'rw', isa => Bool, default => sub{0};

has 'track_init_args', is => 'ro', isa => Maybe[HashRef], default => sub{undef};
has 'build_init_args', is => 'ro', isa => HashRef, required => 1;

around BUILDARGS => sub {
	my $orig = shift;
	my $class = shift;
	my %opts = (ref($_[0]) eq 'HASH') ? %{ $_[0] } : @_; # <-- arg as hash or hashref

	die 'Cannot specify build_init_args in new()' if (exists $opts{build_init_args});
	$opts{build_init_args} = { %opts };
	return $class->$orig(%opts);
};

sub track {
	my $class = shift;
	my %opts = (ref($_[0]) eq 'HASH') ? %{ $_[0] } : @_; # <-- arg as hash or hashref
	die "track cannot be called on object instances" if (ref $class);
	
	# Record the track init arguments:
	$opts{track_init_args} = { %opts };
	
	my $sources = exists $opts{track_sources} ? delete $opts{track_sources} : undef;
	die 'track_sources must be an arrayref' if ($sources and ! ref($sources) eq 'ARRAY');
	my $track_all = exists $opts{track_all_sources} ? delete $opts{track_all_sources} : undef;
	die "track_sources and track_all_sources are incompatable" if ($sources && $track_all);
	
	my $init_sources = exists $opts{init_sources} ? delete $opts{init_sources} : undef;
	die 'init_sources must be an arrayref' if ($init_sources and ! ref($init_sources) eq 'ARRAY');
	my $init_all = exists $opts{init_all_sources} ? delete $opts{init_all_sources} : undef;
	die "init_sources and init_all_sources are incompatable" if ($init_sources && $init_all);
	
	my $collect = exists $opts{collect} ? delete $opts{collect} : undef;
	if ($collect) {
		die "'collect' cannot be used with 'collector_params', 'collector_class' or 'collector'"
			if ($opts{collector_params} || $opts{collector_class} || $opts{collector});
			
		$opts{collector_class} = 'Collector';
		$opts{collector_params} = { collect_coderef => $collect };
	}
	
	if($opts{collector}) {
		die "'collector' cannot be used with 'collector_params', 'collector_class' or 'collect'"
			if ($opts{collector_params} || $opts{collector_class} || $opts{collect});
	}
	
	my $self = $class->new(%opts);
	
	$self->track_sources(@$sources) if ($sources);
	$self->track_all_sources if ($track_all);
	
	$self->init_sources(@$init_sources) if ($init_sources);
	$self->init_all_sources if ($init_all);
	return $self;
}


sub _get_datapoint_configs {
	my $self = shift;
	
	my @configs = DBIx::Class::AuditAny::Util::BuiltinDatapoints->all_configs;
	
	# strip out any being redefined:
	my %cust = map {$_->{name}=>1} @{$self->datapoint_configs};
	@configs = grep { !$cust{$_->{name}} } @configs;
	
	# Set flag to mark the configs that were user defined
	$_->{user_defined} = 1 for (@{$self->datapoint_configs});
	
	push @configs, @{$self->datapoint_configs};
	
	return @configs;
}

has '_datapoints', is => 'ro', isa => HashRef, default => sub {{}};
has '_datapoints_context', is => 'ro', isa => HashRef, default => sub {{}};

# Also index datapoints by 'original_name' which will be different from 'name'
# whenever 'rename_datapoints' has been applied
has '_datapoints_orig_names', is => 'ro', isa => HashRef, default => sub {{}};
sub get_datapoint_orig { (shift)->_datapoints_orig_names->{(shift)} }

sub add_datapoints {
	my $self = shift;
	my $class = $self->default_datapoint_class;
	foreach my $cnf (@_) {
		die "'$cnf' not expected ref" unless (ref $cnf);
		$class = delete $cnf->{class} if ($cnf->{class});
		my $DataPoint = ref($cnf) eq $class ? $cnf : $class->new($cnf);
		die "Error creating datapoint object" unless (ref($DataPoint) eq $class);
		die "Duplicate datapoint name '" . $DataPoint->name . "'" if ($self->_datapoints->{$DataPoint->name});
		$self->_datapoints->{$DataPoint->name} = $DataPoint;
		$self->_datapoints_context->{$DataPoint->context}->{$DataPoint->name} = $DataPoint;
		$self->_datapoints_orig_names->{$DataPoint->original_name} = $DataPoint;
	}
}
sub all_datapoints { values %{(shift)->_datapoints} }

sub get_context_datapoints {
	my $self = shift;
	my @contexts = grep { exists $self->_datapoints_context->{$_} } @_;
	return map { values %{$self->_datapoints_context->{$_}} } @contexts;
}

sub get_context_datapoint_names {
	my $self = shift;
	return map { $_->name } $self->get_context_datapoints(@_);
}


sub local_datapoint_data { (shift)->base_datapoint_values }
has 'base_datapoint_values', is => 'ro', isa => HashRef, lazy => 1, default => sub {
	my $self = shift;
	return { map { $_->name => $_->get_value($self) } $self->get_context_datapoints('base') };
};

sub _init_datapoints {
	my $self = shift;
	
	my @configs = $self->_get_datapoint_configs;
	
	if($self->rename_datapoints) {
		my $rename = $self->rename_datapoints;
		
		@{$self->datapoints} = map { $rename->{$_} || $_ } @{$self->datapoints};
		
		foreach my $cnf (@configs) {
			next unless (exists $rename->{$cnf->{name}});
			$cnf->{original_name} = $cnf->{name};
			$cnf->{name} = $rename->{$cnf->{name}};
		}
	}
	
	my %seen = ();
	$seen{$_}++ and die "Duplicate datapoint name '$_'" for (@{$self->datapoints});
	
	my %disable = map {$_=>1} @{$self->disable_datapoints};
	my %activ = map {$_=>1} grep { !$disable{$_} } @{$self->datapoints};
	
	if($self->auto_include_user_defined_datapoints) {
		$activ{$_->{name}} = 1 for(grep { $_->{name} && $_->{user_defined} } @configs);
	}
	
	foreach my $cnf (@configs) {
		# Do this just to throw the exception for no name:
		$self->add_datapoints($cnf) unless ($cnf->{name});
		
		next unless $activ{$cnf->{name}};
		delete $activ{$cnf->{name}};
		$self->add_datapoints({%$cnf, AuditObj => $self});
	}
	
	die "Unknown datapoint(s) specified (" . join(',',keys %activ) . ')'
		if (scalar(keys %activ) > 0);
}


sub BUILD {
	my $self = shift;
	
	# init all classes first:
	$self->change_context_class;
	$self->changeset_context_class;
	$self->source_context_class;
	$self->column_context_class;
	$self->default_datapoint_class;
	
	$self->_init_datapoints;
	$self->_bind_schema;
	
	# init collector object:
	$self->collector;
}


sub _init_apply_schema_class {
	my $self = shift;
	die "schema is not a reference" unless (ref $self->schema);
	
	Moo::Role->apply_roles_to_object($self->schema,'DBIx::Class::AuditAny::Role::Schema')
		unless try{$self->schema->does('DBIx::Class::AuditAny::Role::Schema')};
	
	# Important!
	$self->schema->_apply_storage_role;
}



sub clear_changeset {
	my $self = shift;
	$self->active_changeset(undef);
	$self->auto_finish(0);
}

sub _bind_schema {
	my $self = shift;
	$self->_init_apply_schema_class;
	
	die "Supplied Schema instance already has a bound Auditor - to allow multple " .
	 "Auditors, set 'allow_multiple_auditors' to true"
		if($self->schema->auditor_count > 0 and ! $self->allow_multiple_auditors);
	
	$_ == $self and return for($self->schema->auditors);
	
	return $self->schema->add_auditor($self);
}




sub track_sources {
	my ($self,@sources) = @_;
	
	foreach my $name (@sources) {
		my $Source = $self->schema->source($name) or die "Bad Result Source name '$name'";
		
		my $class = $self->source_context_class;
		my $AuditSourceContext = $class->new( 
			AuditObj			=> $self, 
			ResultSource	=> $Source
		);
		
		my $source_name = $AuditSourceContext->source;
		
		die "The Log Source (" . $source_name . ") cannot track itself!!"
			if ($source_name ~~ @{$self->log_sources});

		# Skip sources we've already setup:
		return if ($self->tracked_sources->{$source_name});
		
		$self->_add_row_trackers_methods($AuditSourceContext);
		$self->tracked_sources->{$source_name} = $AuditSourceContext;
	}
}

sub track_all_sources {
	my ($self,@exclude) = @_;
	#$class->_init;
	
	push @exclude, @{$self->log_sources};
	
	# temp - auto exclude sources without exactly one primary key
	foreach my $source_name ($self->schema->sources) {
		my $Source = $self->schema->source($source_name);
		push @exclude, $source_name unless (scalar($Source->primary_columns) == 1);
	}
	
	my %excl = map {$_=>1} @exclude;
	return $self->track_sources(grep { !$excl{$_} } $self->schema->sources);
}


sub init_sources {
	my ($self,@sources) = @_;
	
	$self->schema->txn_do(sub {
	
		foreach my $name (@sources) {
			my $SourceContext = $self->tracked_sources->{$name} 
				or die "Source '$name' is not being tracked";
			
			print STDERR "\n";
			
			my $msg = "Initializing Audit Records for $name: ";
			print STDERR $msg . "\r";
			
			my $Rs = $SourceContext->ResultSource->resultset;
			my $total = $Rs->count;
			my $count = 0;
			foreach my $Row ($Rs->all) {
				print STDERR $msg . ++$count . '/' . $total . "\r";
				$Row->audit_init($self);
			}
		}
		
		print STDERR "\n\n";
	});
}

sub init_all_sources {
	my $self = shift;
	$self->init_sources(keys %{$self->track_sources});
}


our $NESTED_CALL = 0;
sub _add_row_trackers_methods {
	my $self = shift;
	my $AuditSourceContext = shift;
	
	my $source_name = $AuditSourceContext->source;
	my $result_class = $self->schema->class($source_name);
	
	foreach my $action (@{$self->track_actions}) {
		my $func_name = $source_name . '::' . $action;
		return if $self->tracked_action_functions->{$func_name}++;
	}
	
	$self->_add_additional_row_methods($result_class);
}

# -- TEMP: bridges for converting away from Row objects
sub _get_old_columns {
	my $self = shift;
	my $Row = $self->_to_origRow(shift);
	return {} unless ($Row && $Row->in_storage);
	return { $Row->get_columns };
}
sub _get_new_columns {
	my $self = shift;
	my $Row = $self->_to_newRow(shift);
	return {} unless ($Row && $Row->in_storage);
	return { $Row->get_columns };
}
sub _to_origRow {
	my $self = shift;
	my $Row = shift;
	return $Row->in_storage ? $Row->get_from_storage : $Row;
}
sub _to_newRow {
	my $self = shift;
	my $Row = shift;
	return $Row unless ($Row->in_storage);
	return $Row->get_from_storage;
}
# --


# TODO/FIXME: This needs to be refactored to use a cleaner API. Probably 
# totally different (this code is leftover from before the switch to the
# Storage Role API)
sub _add_additional_row_methods {
	my $self = shift;
	my $result_class = shift;
	
	my $meta = Class::MOP::Class->initialize($result_class);
	my $immutable = $meta->is_immutable;
	
	die "Won't add tracker/modifier method to immutable Result Class '$result_class' " .
	 '(hint: did you forget to remove __PACKAGE__->meta->make_immutable ??)' .
	 ' - to force/override, set "track_immutable" to true.'
		if ($immutable && !$self->track_immutable);
	
	# Tempory turn mutable back on, saving any immutable_options, first:
	my %immut_opts = ();
	if($immutable) {
		%immut_opts = $meta->immutable_options;
		$meta->make_mutable;
	}
	
	return if ($meta->has_method('audit_take_snapshot'));
	
	$meta->add_method( audit_take_snapshot => sub {
		my $Row = shift;
		my $AuditObj = shift or die "AuditObj not supplied in argument.";
		
		my $Auditors = $Row->result_source->schema->auditors || [];
		my $found = 0;
		$_ == $AuditObj and $found = 1 for (@$Auditors);
		die "Supplied AuditObj is not an active Auditor on this Row's schema instance"
			unless ($found);
		
		my $source_name = $Row->result_source->source_name;
		my $SourceContext = $AuditObj->tracked_sources->{$source_name}
			or die "Source '$source_name' is not being tracked by the supplied Auditor";
		
		unless ($AuditObj->active_changeset) {
			$AuditObj->start_changeset;
			$AuditObj->auto_finish(1);
		}
		
		my $class = $AuditObj->change_context_class;
		my $ChangeContext = $class->new(
			AuditObj				=> $AuditObj,
			SourceContext		=> $SourceContext,
			ChangeSetContext	=> $AuditObj->active_changeset,
			#Row 					=> $Row,
			old_columns			=> $self->_get_old_columns($Row),
			action				=> 'select'
		);
		$ChangeContext->record;
		$AuditObj->record_change($ChangeContext);
		return $Row;
	});
	
	$meta->add_method( audit_init => sub {
		my $Row = shift;
		my $AuditObj = shift or die "AuditObj not supplied in argument.";
		
		my $Auditors = $Row->result_source->schema->auditors || [];
		my $found = 0;
		$_ == $AuditObj and $found = 1 for (@$Auditors);
		die "Supplied AuditObj is not an active Auditor on this Row's schema instance"
			unless ($found);
			
		my $Collector = $AuditObj->collector;
		return $Row->audit_take_snapshot($AuditObj) unless ($Collector->has_full_row_stored($Row));
		return $Row;
	});
	
	# Restore immutability to the way to was:
	$meta->make_immutable(%immut_opts) if ($immutable);
}


##########
##########



sub start_changeset {
	my $self = shift;
	die "Cannot start_changeset because a changeset is already active" if ($self->active_changeset);
	
	my $class = $self->changeset_context_class;
	$self->active_changeset($class->new( AuditObj => $self ));
	return $self->active_changeset;
}

sub finish_changeset {
	my $self = shift;
	die "Cannot finish_changeset because there isn't one active" unless ($self->active_changeset);
	
	unless($self->record_empty_changes) {
		my $count_cols = 0;
		$count_cols = $count_cols + scalar($_->all_column_changes) 
			for (@{$self->active_changeset->changes});
		unless ($count_cols > 0) {
			$self->clear_changeset;
			return 1;
		}
	}
	
	$self->collector->record_changes($self->active_changeset);

	$self->clear_changeset;
	return 1;
}

# this is being replaced with record_changes:
sub record_change {
	my $self = shift;
	my $ChangeContext = shift;
	unless ($self->active_changeset) {
		$self->start_changeset;		
		$self->auto_finish(1);
	}
	#die "Cannot record_change without an active changeset" unless ($self->active_changeset);
	$self->active_changeset->add_changes($ChangeContext);
	$self->finish_changeset if ($self->auto_finish);
}


sub record_changes {
	my ($self, $ChangeContexts) = @_;
	
	my $local_changeset = 0;
	unless ($self->active_changeset) {
		$self->start_changeset;
		$local_changeset = 1;
	}
	
	$self->active_changeset->add_changes($_) for (@$ChangeContexts);
	
	$self->finish_changeset if ($local_changeset);
}


# -- This is a glorified tmp variable used just to allow groups of changes
# to be associated with the correct auditor. TODO: This is probably a 
# poor solution to a complex scoping problem. This exposes us to the 
# risk of processing stale data, so we have to be sure (manually) to keep 
# this clear/empty outside its *very* short lifespan, by regularly resetting it
has '_current_change_group', is => 'rw', isa => ArrayRef[Object], default => sub{[]};
# --

# @inserts is expected as a list of hashrefs with these keys:
# { 
#   to_columns => $hashref
# }
#
sub _start_inserts {
	my ($self, $Source, @inserts) = @_;
	
	$self->_current_change_group([]); # just for good measure
	
	my $source_name = $Source->source_name;
	my $action = 'insert';
	my $func_name = $source_name . '::' . $action;
	
	return () unless ($self->tracked_action_functions->{$func_name});
	
	my @ChangeContexts = map {
		$self->_new_change_context(
			AuditObj				=> $self,
			SourceContext		=> $self->tracked_sources->{$source_name},
			ChangeSetContext	=> $self->active_changeset, # could be undef
			action				=> $action,
			to_columns			=> $_->{to_columns}
		)
	} @inserts;
	
	$self->_current_change_group(\@ChangeContexts);
	return @ChangeContexts;
}

sub _finish_current_change_group {
	my $self = shift;
	$self->record_changes($self->_current_change_group);
	$self->_current_change_group([]); #<-- critical to reset!
}

# factory-like helper:
sub _new_change_context {
	my $self = shift;
	my $class = $self->change_context_class;
	return $class->new(@_);
}




## subs called from hooks in Storage (Role):

sub _record_inserts {
	my ($self, $Source, @inserts) = @_;
	
	my $source_name = $Source->source_name;
	my $action = 'insert';
	my $func_name = $source_name . '::' . $action;
	
	return unless ($self->tracked_action_functions->{$func_name});
	
	my $local_changeset = 0;
	unless ($self->active_changeset) {
		$self->start_changeset;
		$local_changeset = 1;
	}
	
	my $class = $self->change_context_class;
	foreach my $row (@inserts) {
		my $ChangeContext = $class->new(
			AuditObj				=> $self,
			SourceContext		=> $self->tracked_sources->{$source_name},
			ChangeSetContext	=> $self->active_changeset,
			action				=> $action
		);
		$ChangeContext->record($row);
		$self->record_change($ChangeContext);
	}
	
	$self->finish_changeset if ($local_changeset);
}

sub _record_updates {
	my ($self, $Source, @updates) = @_;
	
	my $source_name = $Source->source_name;
	my $action = 'update';
	my $func_name = $source_name . '::' . $action;
	
	return unless ($self->tracked_action_functions->{$func_name});
	
	my $local_changeset = 0;
	unless ($self->active_changeset) {
		$self->start_changeset;
		$local_changeset = 1;
	}
	
	my $class = $self->change_context_class;
	foreach my $update (@updates) {
		my $ChangeContext = $class->new(
			AuditObj				=> $self,
			SourceContext		=> $self->tracked_sources->{$source_name},
			ChangeSetContext	=> $self->active_changeset,
			action				=> $action,
			old_columns			=> $update->{old},
			new_columns			=> $update->{new}
		);
		$ChangeContext->record;
		$self->record_change($ChangeContext);
	}
	
	$self->finish_changeset if ($local_changeset);
}

sub _record_deletes {
	my ($self, $Source, @deletes) = @_;
	
	my $source_name = $Source->source_name;
	my $action = 'delete';
	my $func_name = $source_name . '::' . $action;
	
	return unless ($self->tracked_action_functions->{$func_name});
	
	my $local_changeset = 0;
	unless ($self->active_changeset) {
		$self->start_changeset;
		$local_changeset = 1;
	}
	
	my $class = $self->change_context_class;
	foreach my $row (@deletes) {
		my $ChangeContext = $class->new(
			AuditObj				=> $self,
			SourceContext		=> $self->tracked_sources->{$source_name},
			ChangeSetContext	=> $self->active_changeset,
			action				=> $action,
			old_columns			=> $row,
		);
		$ChangeContext->record;
		$self->record_change($ChangeContext);
	}
	
	$self->finish_changeset if ($local_changeset);
}

1;


__END__

=head1 NAME

DBIx::Class::AuditAny - Flexible change tracking framework for DBIx::Class

=head1 SYNOPSIS

Record all changes into a *separate*, auto-generated and initialized SQLite schema/db 
with default datapoints (Quickest/simplest usage):

Uses the Collector L<DBIx::Class::AuditAny::Collector::AutoDBIC>

 my $schema = My::Schema->connect(@connect);

 use DBIx::Class::AuditAny;

 my $Auditor = DBIx::Class::AuditAny->track(
   schema => $schema, 
   track_all_sources => 1,
   collector_class => 'Collector::AutoDBIC',
   collector_params => {
     sqlite_db => 'db/audit.db',
   }
 );

Record all changes - into specified target sources within the *same*/tracked 
schema - using specific datapoints:

Uses the Collector L<DBIx::Class::AuditAny::Collector::DBIC>

 DBIx::Class::AuditAny->track(
   schema => $schema, 
   track_all_sources => 1,
   collector_class => 'Collector::DBIC',
   collector_params => {
     target_source => 'MyChangeSet',       # ChangeSet source name
     change_data_rel => 'changes',         # Change source, via relationship within ChangeSet
     column_data_rel => 'change_columns',  # ColumnChange source, via relationship within Change
   },
   datapoints => [ # predefined/built-in named datapoints:
     (qw(changeset_ts changeset_elapsed)),
     (qw(change_elapsed action source pri_key_value)),
     (qw(column_name old_value new_value)),
   ],
 );
 
 
Dump raw change data for specific sources (Artist and Album) to a file,
ignore immutable flags in the schema/result classes, and allow more than 
one DBIx::Class::AuditAny Auditor to be attached to the same schema object:

Uses 'collect' sugar param to setup a bare-bones CodeRef Collector (L<DBIx::Class::AuditAny::Collector>)

 my $Auditor = DBIx::Class::AuditAny->track(
   schema => $schema, 
   track_sources => [qw(Artist Album)],
   track_immutable => 1,
   allow_multiple_auditors => 1,
   collect => sub {
     my $cntx = shift;      # ChangeSet context object
     require Data::Dumper;
     print $fh Data::Dumper->Dump([$cntx],[qw(changeset)]);
     
     # Do other custom stuff...
   }
 );


Record all updates (but *not* inserts/deletes) - into specified target sources 
within the same/tracked schema - using specific datapoints, including user-defined 
datapoints and built-in datapoints with custom names:

 DBIx::Class::AuditAny->track(
   schema => CoolCatalystApp->model('Schema')->schema, 
   track_all_sources => 1,
   track_actions => [qw(update)],
   collector_class => 'Collector::DBIC',
   collector_params => {
     target_source => 'MyChangeSet',       # ChangeSet source name
     change_data_rel => 'changes',         # Change source, via relationship within ChangeSet
     column_data_rel => 'change_columns',  # ColumnChange source, via relationship within Change
   },
   datapoints => [
     (qw(changeset_ts changeset_elapsed)),
     (qw(change_elapsed action_id table_name pri_key_value)),
     (qw(column_name old_value new_value)),
   ],
   datapoint_configs => [
     {
       name => 'client_ip',
       context => 'set',
       method => sub {
         my $c = some_func(...);
         return $c->req->address; 
       }
     },
     {
       name => 'user_id',
       context => 'set',
       method => sub {
         my $c = some_func(...);
         $c->user->id;
       }
     }
   ],
   rename_datapoints => {
     changeset_elapsed => 'total_elapsed',
     change_elapsed => 'elapsed',
     pri_key_value => 'row_key',
     new_value => 'new',
     old_value => 'old',
     column_name => 'column',
   },
 );


Record all changes into a user-defined custom Collector class - using
default datapoints:

 my $Auditor = DBIx::Class::AuditAny->track(
   schema => $schema, 
   track_all_sources => 1,
   collector_class => '+MyApp::MyCollector',
   collector_params => {
     foo => 'blah',
     anything => $val
   }
 );


Access/query the audit db of Collector::DBIC and Collector::AutoDBIC collectors:

 my $audit_schema = $Auditor->collector->target_schema;
 $audit_schema->resultset('AuditChangeSet')->search({...});
 
 # Print the ddl that auto-generated and deployed with a Collector::AutoDBIC collector:
 print $audit_schema->resultset('DeployInfo')->first->deployed_ddl;


=head1 DESCRIPTION

This module provides a generalized way to track changes to DBIC databases. The aim is to provide
quick/turn-key options to be able to hit the ground running, while also being highly flexible and
customizable with sane APIs. C<DBIx::Class::AuditAny> wants to be a general framework on top of which other
Change Tracking modules for DBIC can be written.

In progress documentation... In the mean time, see Synopsis and unit tests for examples...

WARNING: this module is still under development and the API is not yet finalized and may be 
changed ahead of v1.000 release.

=head2 API and Usage

AuditAny uses a different API than typical DBIC components. Instead of loading at the schema/result class level with C<load_components>, AudityAny is used by attaching an "Auditor" to an existing schema I<object> instance:

 my $schema = My::Schema->connect(@connect);
 
 my $Auditor = DBIx::Class::AuditAny->track(
   schema => $schema, 
   track_all_sources => 1,
   collector_class => 'Collector::AutoDBIC',
   collector_params => {
     sqlite_db => 'db/audit.db',
   }
 );

The rationale of this approach is that change tracking isn't necesarily something that needs to be, or should be, defined as a built-in attribute of the schema class. Additionally, because of the object-based approach, it is possible to attach multiple Auditors to a single schema object with multiple calls to DBIx::Class::AuditAny->track.


=head1 DATAPOINTS

As changes occur in the tracked schema, information is collected in the form of I<datapoints> at various stages - or I<contexts> - before being passed to the configured Collector. A datapoint has a globally unique name and code used to calculate its value. Code is called at the stage defined by the I<context> of the datapoint. The available contexts are:

=over 4

=item set

=over 5

=item base

=back

=item change

=over 5

=item source

=back

=item column


=back

B<set> (AKA changeset) datapoints are specific to an entire set of changes - insert/update/delete statements grouped in a transaction. Example changeset datapoints include C<changeset_ts> and other broad items. B<base> datapoints are logically the same as B<set> but only need to be calculated once (instead of with every change set). These include things like C<schema> and C<schema_ver>. 

B<change> datapoints apply to a specific C<insert>, C<update> or C<delete> statement, and range from simple items such as C<action> (one of 'insert', 'update' or 'delete') to more exotic and complex items like <column_changes_json>. B<source> datapoints are logically the same as B<change>, but like B<base> datapoints, only need to be calculated once (per source). These include things like C<table_name> and C<source> (source name).

Finally, B<column> datapoints cover information specific to an individual column, such as C<column_name>, C<old_value> and C<new_value>.

There are a number of built-in datapoints (currently stored in L<DBIx::Class::AuditAny::Util::BuiltinDatapoints> which is likely to change), but custom datapoints can also be defined. The Auditor config defines a specific set of datapoints to be calculated (built-in and/or custom). If no datapoints are specified, the default list is used (currently C<change_ts, action, source, pri_key_value, column_name, old_value, new_value>).

The list of datapoints is specified as an ArrayRef in the config. For example:

 datapoints => [qw(action_id column_name new_value)],

=head2 Custom Datapoints

Custom datapoints are specified as HashRef configs with 3 parameters:

=over 4

=item name

The unique name of the datapoint. Should be all lowercase letters, numbers and underscore and must be different from all other datapoints (across all contexts).

=item context

The context of the datapoint: base, source, set, change or column.

=item method

CodeRef to calculate and return the value. The CodeRef is called according to the context, and a different context object is supplied for each context. Each context has its own context object type except B<base> which is supplied the Auditor object itself. See Audit Context Objects below.

=back


Custom datapoints are defined in the C<datapoint_configs> param. After defining a new datapoint config it can then be used like any other datapoint. For example:

 datapoints => [qw(action_id column_name new_value client_ip)],
 datapoint_configs => [
   {
     name => 'client_ip',
     context => 'set',
     method => sub {
       my $contextObj = shift;
       my $c = some_func(...);
       return $c->req->address; 
     }
   }
 ]

=head2 Datapoint Names

Datapoint names must be unique, which means all the built-in datapoint names are reserved. However, if you really want to use an existing datapoint name, or if you want a built-in datapoint to use a different name, you can rename any datapoints like so:

 rename_datapoints => {
   new_value => 'new',
   old_value => 'old',
   column_name => 'column',
 },

=head1 COLLECTORS

Once the Auditor calculates the configured datapoints it passes them to the configured I<Collector>.

...

=head2 Supplied Collector Classes

=over 4

=item L<DBIx::Class::AuditAny::Collector>

=item L<DBIx::Class::AuditAny::Collector::DBIC>

=item L<DBIx::Class::AuditAny::Collector::AutoDBIC>

=back

=head1 AUDIT CONTEXT OBJECTS

...

Inspired in part by the Catalyst Context object design...

=over 4

=item L<DBIx::Class::AuditAny::AuditContext::ChangeSet>

=item L<DBIx::Class::AuditAny::AuditContext::Change>

=item L<DBIx::Class::AuditAny::AuditContext::Column>

=back


=head1 TODO

=over 4

=item Enable tracking multi-primary-key sources (code currently disabled)

=item Write lots more tests 

=item Write lots more docuemntation

=item Expand and finalize API

=item Add more built-in datapoints

=item Review code and get feedback from the perl community for best practices/suggestions

=item Expand the Collector API to be able to provide datapoint configs

=item Separate set/change/column datapoints into 'pre' and 'post' stages

=item Add mechanism to enable/disable tracking (localizable global?)

=back

=head1 SEE ALSO
 
=over 4
 
=item L<DBIx::Class::AuditLog>
 
=item L<DBIx::Class::Journal>
 
=back

=cut
