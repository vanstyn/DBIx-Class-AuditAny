package DBIx::Class::AuditAny::DataPoint;
use strict;
use warnings;

# VERSION
# ABSTRACT: Object class for AuditAny datapoint configs

# This class defines the *config* of a datapoint, not the *value* 
# of the datapoint. It is used to get the value, but the value itself
# is not stored within this object. Datapoint values are stored within 
# the Context objects whose life-cycle is limited to individual tracked 
# database operations


use Moo;
use MooX::Types::MooseLike::Base 0.19 qw(:all);

use Switch qw(switch);

has 'AuditObj', is => 'ro', isa => InstanceOf['DBIx::Class::AuditAny'], required => 1;

# The unique name of the DataPoint (i.e. 'key')
has 'name', is => 'ro', isa => Str, required => 1;

# The name of the -context-; determines at what point the value 
# should be computed and collected, and into which Context -object-
# it will be stored
has 'context', is => 'ro', required => 1,
 isa => Enum[qw(base source set change column)];

# Additional classification used with context to determine when to
# collect the value for a datapoint. Either 'pre' or 'post' to denote
# collection before or after the wrapped database operation. Logically, 
# there are stage*context possible collection points, although stage 
# isn't considered for contexts where it doesn't apply, like in 'base' 
# and 'source'
has 'stage', is => 'ro', isa => Enum[qw(pre post)], default => sub{'post'};

# method is what is called to get the value of the datapoint. It is a 
# CodeRef and is supplied the Context object (ChangeSet, Change, Column, etc)
# as the first argument. As a convenience, it can also be a Str in which
# case it is an existing method name within the Context object
has 'method', is => 'ro', isa => AnyOf[CodeRef,Str], required => 1;

# Informational flag set to identify if this datapoint has been
# defined custom, on-the-fly, or is a built-in
has 'user_defined', is => 'ro', isa => Bool, default => sub{0};

# Optional extra attr to keep track of a separate 'original' name. Auto
# set when 'rename_datapoints' are specified (see top DBIx::Class::AuditAny class)
has 'original_name', is => 'ro', isa => Str, lazy => 1, 
 default => sub { (shift)->name };

# -- column_info defines the schema needed to store this datapoint within
# a DBIC Result/table. Only used in collectors like Collector::AutoDBIC
has 'column_info', is => 'ro', isa => HashRef, lazy => 1, 
 default => sub { my $self = shift; $self->get_column_info->($self) };
 
has 'get_column_info', is => 'ro', isa => CodeRef, lazy => 1,
 default => sub {{ data_type => "varchar" }};
# --

sub BUILD {
	my $self = shift;
	
	my @contexts = qw(base source set change column);
	die "Bad data point context '" . $self->context . "' - allowed values: " . join(',',@contexts)
		unless ($self->context ~~ @contexts);
		
	die "Bad datapoint name '" . $self->name . "' - only lowercase letters, numbers, underscore(_) and dash(-) allowed" 
		unless ($self->name =~ /^[a-z0-9\_\-]+$/);
}

sub get_value {
	my $self = shift;
	my $Context = shift;
	my $method = $self->method;
	return ref($method) ? $method->($self,$Context,@_) : $Context->$method(@_);
}

1;