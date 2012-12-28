package DBIx::Class::AuditAny::Collector::AutoDBIC;
use Moose;
extends 'DBIx::Class::AuditAny::Collector::DBIC';

# VERSION

use DBIx::Class::AuditAny::Util;
use DBIx::Class::AuditAny::Util::SchemaMaker;
use String::CamelCase qw(camelize decamelize);

has 'connect', is => 'ro', isa => 'ArrayRef', lazy => 1, default => sub {
	my $self = shift;
	my $db = $self->sqlite_db or die "no 'connect' or 'sqlite_db' specified.";
	return [ "dbi:SQLite:dbname=$db","","", { AutoCommit => 1 } ];
};

has 'sqlite_db', is => 'ro', isa => 'Maybe[Str]', default => undef;
has 'auto_deploy', is => 'ro', isa => 'Bool', default => 1;

has 'target_schema_namespace', is => 'ro', lazy => 1, default => sub {
	my $self = shift;
	return ref($self->AuditObj->schema) . '::AuditSchema';
};

has '+target_schema', default => sub {
	my $self = shift;
	
	my $class = $self->init_schema_namespace;
	my $schema = $class->connect(@{$self->connect});
	$schema->deploy if ($self->auto_deploy);
	
	return $schema;
};

has 'target_source', is => 'ro', isa => 'Str', lazy => 1, 
 default => sub { (shift)->changeset_source_name };

has 'changeset_source_name', 		is => 'ro', isa => 'Str', default => 'AuditChangeSet';
has 'change_source_name', 			is => 'ro', isa => 'Str', default => 'AuditChange';
has 'column_change_source_name',	is => 'ro', isa => 'Str', default => 'AuditChangeColumn';

has 'changeset_table_name', is => 'ro', isa => 'Str', lazy => 1, 
 default => sub { decamelize((shift)->changeset_source_name) };
	
has 'change_table_name', is => 'ro', isa => 'Str', lazy => 1, 
 default => sub { decamelize((shift)->change_source_name) };
	
has 'column_change_table_name',	is => 'ro', isa => 'Str', lazy => 1, 
 default => sub { decamelize((shift)->column_change_source_name) };

has '+change_data_rel', default => 'audit_changes';
has '+column_data_rel', default => 'audit_change_columns';
has 'reverse_change_data_rel', is => 'ro', isa => 'Str', default => 'change';
has 'reverse_changeset_data_rel', is => 'ro', isa => 'Str', default => 'changeset';

has 'changeset_columns', is => 'ro', isa => 'ArrayRef', lazy => 1,
 default => sub {
	my $self = shift;
	return [
		id => {
			data_type => "integer",
			extra => { unsigned => 1 },
			is_auto_increment => 1,
			is_nullable => 0,
		},
		$self->get_context_column_infos(qw(base set))
	];
};

has 'change_columns', is => 'ro', isa => 'ArrayRef', lazy => 1,
 default => sub {
	my $self = shift;
	return [
		id => {
			data_type => "integer",
			extra => { unsigned => 1 },
			is_auto_increment => 1,
			is_nullable => 0,
		}, 
		changeset_id => {
			data_type => "integer",
			extra => { unsigned => 1 },
			is_foreign_key => 1,
			is_nullable => 0,
		},
		$self->get_context_column_infos(qw(source change))
	];
};

has 'change_column_columns', is => 'ro', isa => 'ArrayRef', lazy => 1,
 default => sub {
	my $self = shift;
	return [
		id => {
			data_type => "integer",
			extra => { unsigned => 1 },
			is_auto_increment => 1,
			is_nullable => 0,
		}, 
		change_id => {
			data_type => "integer",
			extra => { unsigned => 1 },
			is_foreign_key => 1,
			is_nullable => 0,
		},
		$self->get_context_column_infos(qw(column))
	];
};

# Gets and validates DBIC column configs per supplied datapoint contexts
sub get_context_column_infos {
	my $self = shift;
	my @DataPoints = $self->AuditObj->get_context_datapoints(@_);
	return () unless (scalar @DataPoints > 0);
	
	my %reserved 		= map {$_=>1} qw(id changeset_id change_id);
	my %no_accessor 	= map {$_=>1} qw(new meta);
	
	my @cols = ();
	foreach my $DataPoint (@DataPoints) {
		my $name = $DataPoint->name;
		my $info = $DataPoint->column_info;
		$reserved{$name}		and die "Bad datapoint name '$name' - reserved keyword.";
		$no_accessor{$name}	and $info->{accessor} = undef;
		push @cols, ( $name => $info );
	}
	
	return @cols;
}

sub init_schema_namespace {
	my $self = shift;
	
	my $namespace = $self->target_schema_namespace;
	return DBIx::Class::AuditAny::Util::SchemaMaker->initialize(
		schema_namespace => $namespace,
		results => {
			$self->changeset_source_name => {
				table_name => $self->changeset_table_name,
				columns => $self->changeset_columns,
				call_class_methods => [
					set_primary_key => ['id'],
					has_many => [
						$self->change_data_rel,
						$namespace . '::' . $self->change_source_name,
						{ "foreign.changeset_id" => "self.id" },
						{ cascade_copy => 0, cascade_delete => 0 },
					]
				]
			},
			$self->change_source_name => {
				table_name => $self->change_table_name,
				columns => $self->change_columns,
				call_class_methods => [
					set_primary_key => ['id'],
					belongs_to => [
						$self->reverse_changeset_data_rel,
						$namespace . '::' . $self->changeset_source_name,
						{ id => "changeset_id" },
						{ is_deferrable => 1, on_delete => "CASCADE", on_update => "CASCADE" },
					],
					has_many => [
						$self->column_data_rel,
						$namespace . '::' . $self->column_change_source_name,
						{ "foreign.change_id" => "self.id" },
						{ cascade_copy => 0, cascade_delete => 0 },
					]
				]
			},
			$self->column_change_source_name => {
				table_name => $self->column_change_table_name,
				columns => $self->change_column_columns,
				call_class_methods => [
					set_primary_key => ['id'],
					add_unique_constraint => ["change_id", ["change_id", "column"]],
					belongs_to => [
						  $self->reverse_change_data_rel,
							$namespace . '::' . $self->change_source_name,
							{ id => "change_id" },
							{ is_deferrable => 1, on_delete => "CASCADE", on_update => "CASCADE" },
					],
				]
			}
		}
	);
}

1;
