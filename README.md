DBIx-Class-AuditAny
===================

Flexible change tracking framework for DBIx::Class

See POD in main class DBIx::Class::AuditAny

-------------------


Copied/Converted POD (in-progress)
-----------------------------------

# NAME

DBIx::Class::AuditAny - Flexible change tracking framework for DBIx::Class

# SYNOPSIS

Record all changes into a \*separate\*, auto-generated and initialized SQLite schema/db 
with default datapoints (Quickest/simplest usage):

Uses the Collector [DBIx::Class::AuditAny::Collector::AutoDBIC](http://search.cpan.org/perldoc?DBIx::Class::AuditAny::Collector::AutoDBIC)

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

Record all changes - into specified target sources within the \*same\*/tracked 
schema - using specific datapoints:

Uses the Collector [DBIx::Class::AuditAny::Collector::DBIC](http://search.cpan.org/perldoc?DBIx::Class::AuditAny::Collector::DBIC)

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

Uses 'collect' sugar param to setup a bare-bones CodeRef Collector ([DBIx::Class::AuditAny::Collector](http://search.cpan.org/perldoc?DBIx::Class::AuditAny::Collector))

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



Record all updates (but \*not\* inserts/deletes) - into specified target sources 
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



# DESCRIPTION

This module provides a generalized way to track changes to DBIC databases. The aim is to provide
quick/turn-key options to be able to hit the ground running, while also being highly flexible and
customizable with sane APIs. `DBIx::Class::AuditAny` wants to be a general framework on top of which other
Change Tracking modules for DBIC can be written.

In progress documentation... In the mean time, see Synopsis and unit tests for examples...

WARNING: this module is still under development and the API is not yet finalized and may be 
changed ahead of v1.000 release.

## API and Usage

AuditAny uses a different API than typical DBIC components. Instead of loading at the schema/result class level with `load_components`, AudityAny is used by attaching an "Auditor" to an existing schema _object_ instance:

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



# DATAPOINTS

As changes occur in the tracked schema, information is collected in the form of _datapoints_ at various stages - or _contexts_ - before being passed to the configured Collector. A datapoint has a globally unique name and code used to calculate its value. Code is called at the stage defined by the _context_ of the datapoint. The available contexts are:

- set
    - base
- change
    - source
- column



__set__ (AKA changeset) datapoints are specific to an entire set of changes - insert/update/delete statements grouped in a transaction. Example changeset datapoints include `changeset_ts` and other broad items. __base__ datapoints are logically the same as __set__ but only need to be calculated once (instead of with every change set). These include things like `schema` and `schema_ver`. 

__change__ datapoints apply to a specific `insert`, `update` or `delete` statement, and range from simple items such as `action` (one of 'insert', 'update' or 'delete') to more exotic and complex items like <column\_changes\_json>. __source__ datapoints are logically the same as __change__, but like __base__ datapoints, only need to be calculated once (per source). These include things like `table_name` and `source` (source name).

Finally, __column__ datapoints cover information specific to an individual column, such as `column_name`, `old_value` and `new_value`.

There are a number of built-in datapoints (currently stored in [DBIx::Class::AuditAny::Util::BuiltinDatapoints](http://search.cpan.org/perldoc?DBIx::Class::AuditAny::Util::BuiltinDatapoints) which is likely to change), but custom datapoints can also be defined. The Auditor config defines a specific set of datapoints to be calculated (built-in and/or custom). If no datapoints are specified, the default list is used (currently `change_ts, action, source, pri_key_value, column_name, old_value, new_value`).

The list of datapoints is specified as an ArrayRef in the config. For example:

    datapoints => [qw(action_id column_name new_value)],

## Custom Datapoints

Custom datapoints are specified as HashRef configs with 3 parameters:

- name

    The unique name of the datapoint. Should be all lowercase letters, numbers and underscore and must be different from all other datapoints (across all contexts).

- context

    The context of the datapoint: base, source, set, change or column.

- method

    CodeRef to calculate and return the value. The CodeRef is called according to the context, and a different context object is supplied for each context. Each context has its own context object type except __base__ which is supplied the Auditor object itself. See Audit Context Objects below.



Custom datapoints are defined in the `datapoint_configs` param. After defining a new datapoint config it can then be used like any other datapoint. For example:

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

## Datapoint Names

Datapoint names must be unique, which means all the built-in datapoint names are reserved. However, if you really want to use an existing datapoint name, or if you want a built-in datapoint to use a different name, you can rename any datapoints like so:

    rename_datapoints => {
      new_value => 'new',
      old_value => 'old',
      column_name => 'column',
    },

# COLLECTORS

Once the Auditor calculates the configured datapoints it passes them to the configured _Collector_.

...

## Supplied Collector Classes

- [DBIx::Class::AuditAny::Collector](http://search.cpan.org/perldoc?DBIx::Class::AuditAny::Collector)
- [DBIx::Class::AuditAny::Collector::DBIC](http://search.cpan.org/perldoc?DBIx::Class::AuditAny::Collector::DBIC)
- [DBIx::Class::AuditAny::Collector::AutoDBIC](http://search.cpan.org/perldoc?DBIx::Class::AuditAny::Collector::AutoDBIC)

# AUDIT CONTEXT OBJECTS

...

Inspired in part by the Catalyst Context object design...

- [DBIx::Class::AuditAny::AuditContext::ChangeSet](http://search.cpan.org/perldoc?DBIx::Class::AuditAny::AuditContext::ChangeSet)
- [DBIx::Class::AuditAny::AuditContext::Change](http://search.cpan.org/perldoc?DBIx::Class::AuditAny::AuditContext::Change)
- [DBIx::Class::AuditAny::AuditContext::Column](http://search.cpan.org/perldoc?DBIx::Class::AuditAny::AuditContext::Column)



# TODO

- Enable tracking multi-primary-key sources (code currently disabled)
- Write lots more tests 
- Write lots more docuemntation
- Expand and finalize API
- Add more built-in datapoints
- Review code and get feedback from the perl community for best practices/suggestions
- Expand the Collector API to be able to provide datapoint configs
- Separate set/change/column datapoints into 'pre' and 'post' stages
- Add mechanism to enable/disable tracking (localizable global?)

# SEE ALSO
 

- [DBIx::Class::AuditLog](http://search.cpan.org/perldoc?DBIx::Class::AuditLog)
 
- [DBIx::Class::Journal](http://search.cpan.org/perldoc?DBIx::Class::Journal)
