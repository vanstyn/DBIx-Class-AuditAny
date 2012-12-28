package # Hide from PAUSE 
    DBIx::Class::AuditAny::Util::BuiltinDatapoints;

# VERSION
# ABSTRACT: Built-in datapoint configs for DBIx::Class::AuditAny

use strict;
use warnings;

# This are just lists of predefined configs ($hashref) - constructor arguments 
# for DBIx::Class::AuditAny::DataPoint->new(%$hashref)

sub all_configs {(
	&base_context,
	&source_context,
	&set_context,
	&change_context,
	&column_context,
)}


sub base_context {
	map {{ context => 'base', %$_ }} (
		{
			name 			=> 'schema', 
			method		=> sub { ref((shift)->AuditObj->schema) },
			column_info	=> { data_type => "varchar", is_nullable => 0, size => 255 } 
		},
		{
			name 			=> 'schema_ver', 
			method		=> sub { (shift)->AuditObj->schema->schema_version },
			column_info	=> { data_type => "varchar", is_nullable => 1, size => 16 } 
		}
	)
}

# set 'method' as a direct passthrough to $Context->'name' per default (see DataPoint class)
sub source_context {
	map {{ context => 'source', method => $_->{name}, %$_ }} (
		{
			name 			=> 'source', 
			column_info	=> { data_type => "varchar", is_nullable => 0, size => 255 } 
		},
		{
			name 			=> 'class', 
			column_info	=> { data_type => "varchar", is_nullable => 0, size => 255 } 
		},
		{
			name 			=> 'from', 
			column_info	=> { data_type => "varchar", is_nullable => 0, size => 128 } 
		},
		{
			name 			=> 'table', 
			column_info	=> { data_type => "varchar", is_nullable => 0, size => 128 } 
		},
		{
			name 			=> 'pri_key_column', 
			column_info	=> { data_type => "varchar", is_nullable => 0, size => 64 } 
		},
		{
			name 			=> 'pri_key_count', 
			column_info	=> { data_type => "integer", extra => { unsigned => 1 }, is_nullable => 0 } 
		}
	)
}

# set 'method' as a direct passthrough to $Context->'name' per default (see DataPoint class)
sub set_context {
	map {{ context => 'set', method => $_->{name}, %$_ }} (
		{
			name 			=> 'changeset_ts', 
			column_info	=> { 
				data_type => "datetime",
				datetime_undef_if_invalid => 1,
				is_nullable => 0
			} 
		},
		{
			name 			=> 'changeset_finish_ts', 
			column_info	=> { 
				data_type => "datetime",
				datetime_undef_if_invalid => 1,
				is_nullable => 0
			} 
		},
		{
			name 			=> 'changeset_elapsed', 
			column_info	=> { data_type => "varchar", is_nullable => 0, size => 16 } 
		},
	)
}

# set 'method' as a direct passthrough to $Context->'name' per default (see DataPoint class)
sub change_context {
	map {{ context => 'change', method => $_->{name}, %$_ }} (
		{
			name 			=> 'change_ts', 
			column_info	=> { 
				data_type => "datetime",
				datetime_undef_if_invalid => 1,
				is_nullable => 0
			} 
		},
		{
			name 			=> 'action', 
			column_info	=> { data_type => "char", is_nullable => 0, size => 6 }
		},
		{
			name 			=> 'action_id', 
			column_info	=> { data_type => "integer", is_nullable => 0 }
		},
		{
			name 			=> 'pri_key_value', 
			column_info	=> { data_type => "varchar", is_nullable => 0, size => 255 } 
		},
		{
			name 			=> 'orig_pri_key_value', 
			column_info	=> { data_type => "varchar", is_nullable => 0, size => 255 } 
		},
		{
			name 			=> 'change_elapsed', 
			column_info	=> { data_type => "varchar", is_nullable => 0, size => 16 } 
		},
		{
			name 			=> 'column_changes_json', 
			column_info	=> { data_type => "mediumtext", is_nullable => 1 } 
		},
		{
			name 			=> 'column_changes_ascii', 
			column_info	=> { data_type => "mediumtext", is_nullable => 1 } 
		},
	)
}

# set 'method' as a direct passthrough to $Context->'name' per default (see DataPoint class)
sub column_context {
	map {{ context => 'column', method => $_->{name}, %$_ }} (
		{
			name 			=> 'column_header', 
			column_info	=>  { data_type => "varchar", is_nullable => 0, size => 128 } 
		},
		{
			name 			=> 'column_name', 
			column_info	=>  { data_type => "varchar", is_nullable => 0, size => 128 } 
		},
		{
			name 			=> 'old_value', 
			column_info	=> { data_type => "mediumtext", is_nullable => 1 } 
		},
		{
			name 			=> 'new_value', 
			column_info	=> { data_type => "mediumtext", is_nullable => 1 } 
		},
		{
			name 			=> 'old_display_value', 
			column_info	=> { data_type => "mediumtext", is_nullable => 1 } 
		},
		{
			name 			=> 'new_display_value', 
			column_info	=> { data_type => "mediumtext", is_nullable => 1 } 
		},
	)
}


1;