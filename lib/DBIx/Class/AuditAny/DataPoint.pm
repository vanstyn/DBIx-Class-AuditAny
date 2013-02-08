package DBIx::Class::AuditAny::DataPoint;
use strict;
use warnings;

# VERSION
# ABSTRACT: Object class for AuditAny datapoint configs

use Moo;
use MooX::Types::MooseLike::Base 0.17 qw(:all);

#use Moose;
#use MooseX::Types::Moose qw(HashRef ArrayRef Str Bool Maybe Object CodeRef);

# ----
# MooX::Types::MooseLike::Base has no union support ( isa => Str | CodeRef ):
# UPDATE: 'AnyOf' was added in MooX::Types::MooseLike::Base 0.17
#  used for:  isa => AnyOf['Str','CodeRef']  below
#   note: per IRC discussions, the AnyOf API may change 
#   in MooX::Types::MooseLike::Base 0.18 to use non-string params
#
#my $StrCodeRef = sub {
#	(! ref($_[0]) || ref($_[0]) eq 'CODE') or
#		die "$_[0] is not a Str or a CodeRef";
#};
# ----

use Switch qw(switch);

has 'AuditObj', is => 'ro', isa => InstanceOf['DBIx::Class::AuditAny'], required => 1;
has 'name', is => 'ro', isa => Str, required => 1;
has 'context', is => 'ro', isa => Str, required => 1;
has 'method', is => 'ro', isa => AnyOf['Str','CodeRef'], required => 1;
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