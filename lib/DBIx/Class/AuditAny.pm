package DBIx::Class::AuditAny;
use strict;
use warnings;
use Moose;

# VERSION
# ABSTRACT: Flexible change tracking framework for DBIx::Class

use Class::MOP::Class;
use DateTime;
use DBIx::Class::AuditAny::Util;
use DBIx::Class::AuditAny::Util::BuiltinDatapoints;

has 'time_zone', is => 'ro', isa => 'Str', default => 'local';
sub get_dt { DateTime->now( time_zone => (shift)->time_zone ) }

has 'schema', is => 'ro', required => 1, isa => 'DBIx::Class::Schema';
has 'track_immutable', is => 'ro', isa => 'Bool', default => 0;
has 'track_actions', is => 'ro', isa => 'ArrayRef', default => sub { [qw(insert update delete)] };
has 'allow_multiple_auditors', is => 'ro', isa => 'Bool', default => 0;


has 'source_context_class', is => 'ro', default => 'AuditContext::Source';
has 'change_context_class', is => 'ro', default => 'AuditContext::Change';
has 'changeset_context_class', is => 'ro', default => 'AuditContext::ChangeSet';
has 'column_context_class', is => 'ro', default => 'AuditContext::Column';
has 'default_datapoint_class', is => 'ro', default => 'DataPoint';
has 'collector_class', is => 'ro', isa => 'Str';

around $_ => sub { 
	my $orig = shift; my $self = shift; 
	resolve_localclass $self->$orig(@_);
} for qw(
 source_context_class change_context_class
 changeset_context_class column_context_class
 default_datapoint_class collector_class
);

has 'collector_params', is => 'ro', isa => 'HashRef', default => sub {{}};
has 'primary_key_separator', is => 'ro', isa => 'Str', default => '|~|';
has 'datapoints', is => 'ro', isa => 'ArrayRef[Str]', lazy_build => 1;
has 'datapoint_configs', is => 'ro', isa => 'ArrayRef[HashRef]', default => sub {[]};
has 'auto_include_user_defined_datapoints', is => 'ro', isa => 'Bool', default => 1;
has 'rename_datapoints', is => 'ro', isa => 'Maybe[HashRef[Str]]', default => undef;
has 'disable_datapoints', is => 'ro', isa => 'ArrayRef', default => sub {[]};
has 'record_empty_changes', is => 'ro', isa => 'Bool', default => 0;

has 'collector', is => 'ro', lazy => 1, default => sub {
	my $self = shift;
	return ($self->collector_class)->new(
		%{$self->collector_params},
		AuditObj => $self
	);
};

# Any sources within the tracked schema that the collector is writing to; these
# sources are not allowed to be tracked because it would create infinite recursion:
has 'log_sources', is => 'ro', isa => 'ArrayRef[Str]', lazy => 1, init_arg => undef, default => sub {
	my $self = shift;
	return $self->collector->writes_bound_schema_sources;
};

has 'tracked_action_functions', is => 'ro', isa => 'HashRef', default => sub {{}};
has 'tracked_sources', is => 'ro', isa => 'HashRef[Str]', default => sub {{}};
has 'calling_action_function', is => 'ro', isa => 'HashRef[Bool]', default => sub {{}};
has 'active_changeset', is => 'rw', isa => 'Maybe[Object]', default => undef;
has 'auto_finish', is => 'rw', isa => 'Bool', default => 0;

has 'track_init_args', is => 'ro', isa => 'Maybe[HashRef]', default => undef;
has 'build_init_args', is => 'ro', isa => 'HashRef', required => 1;

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

# Default enabled datapoints if none are specified:
sub _build_datapoints {[qw(
change_ts
action
source
pri_key_value
column_name
old_value
new_value
)]};


has '_datapoints', is => 'ro', isa => 'HashRef', default => sub {{}};
has '_datapoints_context', is => 'ro', isa => 'HashRef', default => sub {{}};

# Also index datapoints by 'original_name' which will be different from 'name'
# whenever 'rename_datapoints' has been applied
has '_datapoints_orig_names', is => 'ro', isa => 'HashRef', default => sub {{}};
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
has 'base_datapoint_values', is => 'ro', isa => 'HashRef', lazy => 1, default => sub {
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
	return if ($self->schema->can('auditors'));
	my $class = ref($self->schema) or die "schema is not a reference";
	
	my $meta = Class::MOP::Class->initialize($class);
	
	# If this class has already be updated:
	return if ($meta->has_attribute('auditors'));
	
	my $immutable = $meta->is_immutable;
	
	die "Won't add 'auditany' attribute to immutable Schema Class '$class' " .
	 '(hint: did you forget to remove __PACKAGE__->meta->make_immutable ??)' .
	 ' - to force/override, set "track_immutable" to true.'
		if ($immutable && !$self->track_immutable);
	
	# Tempory turn mutable back on, saving any immutable_options, first:
	my %immut_opts = ();
	if($immutable) {
		%immut_opts = $meta->immutable_options;
		$meta->make_mutable;
	}
	
	$meta->add_attribute( 
		auditors => ( 
			accessor => 'auditors',
			reader => 'auditors',
			writer => 'set_auditors',
			default => undef
		)
	);
	$meta->add_method( add_auditor => sub { push @{(shift)->auditors}, @_ } );
	
	$meta->add_around_method_modifier( 'txn_do' => sub {
		my $orig = shift;
		my $Schema = shift;
		
		# This method modifier is applied to the entire schema class. Call/return the
		# unaltered original method unless the Row is tied to a schema instance that
		# is being tracked by an AuditAny which is configured to track the current
		# action function. Also, make sure this call is not already nested to prevent
		# deep recursion
		my $Auditors = $Schema->auditors || [];
		return $Schema->$orig(@_) unless (scalar(@$Auditors) > 0);
		
		my @ChangeSets = ();
		foreach my $AuditAny (@$Auditors) {
			next if (
				ref($self) ne ref($AuditAny) ||
				$AuditAny->active_changeset
			);
			push @ChangeSets, $AuditAny->start_changeset;
		};
		
		return $Schema->$orig(@_) unless (scalar(@ChangeSets) > 0);
		
		my $result;
		my @args = @_;
		try {
			$result = $Schema->$orig(@args);
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
	});
		
	$meta->make_immutable(%immut_opts) if ($immutable);
}

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

sub clear_changeset {
	my $self = shift;
	$self->active_changeset(undef);
	$self->auto_finish(0);
}

sub _bind_schema {
	my $self = shift;
	$self->_init_apply_schema_class;
	
	$self->schema->set_auditors([]) unless ($self->schema->auditors);
	
	die "Supplied Schema instance already has a bound Auditor - to allow multple " .
	 "Auditors, set 'allow_multiple_auditors' to true"
		if(scalar(@{$self->schema->auditors}) > 0 and ! $self->allow_multiple_auditors);
	
	$_ == $self and return for(@{$self->schema->auditors});
	
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
	
	foreach my $action (@{$self->track_actions}) {

		my $func_name = $result_class . '::' . $action;
		
		return if $self->tracked_action_functions->{$func_name}++;
		
		my $applied_attr = '_auditany_' . $action . '_tracker_applied';
		return if ($result_class->can($applied_attr));

		$meta->add_around_method_modifier( $action => sub {
			my $orig = shift;
			my $Row = shift;
		
			# This method modifier is applied to the entire result class. Call/return the
			# unaltered original method unless the Row is tied to a schema instance that
			# is being tracked by an AuditAny which is configured to track the current
			# action function. Also, make sure this call is not already nested to prevent
			# deep recursion
			my $Auditors = $Row->result_source->schema->auditors || [];
			return $Row->$orig(@_) unless (scalar(@$Auditors) > 0);
			
			# Before action is called:
			my @Trackers = ();
			foreach my $AuditAny (@$Auditors) {
				next if (
					ref($self) ne ref($AuditAny) ||
					! $AuditAny->tracked_action_functions->{$func_name} ||
					$AuditAny->calling_action_function->{$func_name}
				);
				
				unless ($AuditAny->active_changeset) {
					$AuditAny->start_changeset;
					$AuditAny->auto_finish(1);
				}
				
				$AuditAny->calling_action_function->{$func_name} = 1;
				my $class = $AuditAny->change_context_class;
				my $ChangeContext = $class->new(
					AuditObj				=> $AuditAny,
					SourceContext		=> $AuditAny->tracked_sources->{$source_name},
					ChangeSetContext	=> $AuditAny->active_changeset,
					Row 					=> $Row,
					action				=> $action
				) or next;
				push @Trackers, $ChangeContext;
			}
			
			my $result;
			my @args = @_;
			try {
				# call action:
				$result = $Row->$orig(@args);
				
				# After action is called:
				foreach my $ChangeContext (@Trackers) {
					$ChangeContext->record;
					my $AuditAny = $ChangeContext->AuditObj;
					$AuditAny->record_change($ChangeContext);
					$AuditAny->calling_action_function->{$func_name} = 0;
				}
			}
			catch {
				my $err = shift;
				# Still Clean up:
				foreach my $ChangeContext (@Trackers) {
					try {
						my $AuditAny = $ChangeContext->AuditObj;
						try{$AuditAny->clear_changeset};
						$AuditAny->calling_action_function->{$func_name} = 0;
					};
				}
				# Re-throw:
				die $err;
			};
			return $result;
		}) or die "Unknown error setting up '$action' modifier on '$result_class'";
		
		$result_class->mk_classdata($applied_attr);
		$result_class->$applied_attr(1);
		
	}
	
	$self->_add_additional_row_methods($meta);
	
	# Restore immutability to the way to was:
	$meta->make_immutable(%immut_opts) if ($immutable);
}


sub _add_additional_row_methods {
	my $self = shift;
	my $meta = shift;
	
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
			Row 					=> $Row,
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
}


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


1;


__END__

=head1 SYNOPSIS

 use DBIx::Class::AuditAny;

 # Record all changes into a separate, auto-generated and initialized SQLite schema/db 
 # with default datapoints (Quickest/simplest usage):
 my $Auditor = DBIx::Class::AuditAny->track(
   schema => $schema, 
   track_all_sources => 1,
   collector_class => 'Collector::AutoDBIC',
   collector_params => {
     sqlite_db => 'db/audit.db',
   }
 );
 
 
 # Record all changes - into specified target sources within the same/tracked 
 # schema - using specific datapoints:
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
 
 
 # Dump raw change data for specific sources (Artist and Album) to a file,
 # ignore immutable flags in the schema/result classes, and allow more than 
 # one DBIx::Class::AuditAny Auditor to be attached to the same schema object:
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
 
 
 # Record all updates (but *not* inserts/deletes) - into specified target sources 
 # within the same/tracked schema - using specific datapoints, including user-defined 
 # datapoints and built-in datapoints with custom names:
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
 
 
 # Record all changes into a user-defined custom Collector class - using
 # default datapoints:
 my $Auditor = DBIx::Class::AuditAny->track(
   schema => $schema, 
   track_all_sources => 1,
   collector_class => '+MyApp::MyCollector',
   collector_params => {
     foo => 'blah',
     anything => $val
   }
 );
 
 
 # Access/query the audit db of Collector::DBIC and Collector::AutoDBIC collectors:
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

=head1 DATAPOINTS

...

Built-in datapoint config definitions currently stored in L<DBIx::Class::AuditAny::Util::BuiltinDatapoints> (likely to change)

=head1 COLLECTORS

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

=item Write lots more tests 

=item Write lots more docuemntation

=item Expand and finalize API

=item Add more built-in datapoints

=item Review code and get feedback from the perl community for best practices/suggestions

=back

=head1 SEE ALSO
 
=over 4
 
=item L<DBIx::Class::AuditLog>
 
=item L<DBIx::Class::Journal>
 
=back

=cut
