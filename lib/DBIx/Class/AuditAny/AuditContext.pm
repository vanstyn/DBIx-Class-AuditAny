package # Hide from PAUSE 
     DBIx::Class::AuditAny::AuditContext;
use strict;
use warnings;

# VERSION
# ABSTRACT: Base class for context objects in DBIx::Class::AuditAny

use Moo;
use MooX::Types::MooseLike::Base qw(:all);

#use Moose;
#use MooseX::AttributeShortcuts; # gives us: is => 'lazy' (see lazy_build)

has 'AuditObj', is => 'ro', isa => InstanceOf['DBIx::Class::AuditAny'], required => 1;

has 'tiedContexts', is => 'lazy', isa => ArrayRef[Object];#, lazy_build => 1;
has 'local_datapoint_data', is => 'lazy', isa => HashRef;#, lazy_build => 1;

sub _build_tiedContexts { die "Virtual method" }
sub _build_local_datapoint_data { die "Virtual method" }

sub get_datapoint_value {
	my $self = shift;
	my $name = shift;
	my @Contexts = ($self,@{$self->tiedContexts},$self->AuditObj);
	foreach my $Context (@Contexts) {
		return $Context->local_datapoint_data->{$name} 
			if (exists $Context->local_datapoint_data->{$name});
	}
	die "Unknown datapoint '$name'";
}

sub get_datapoints_data {
	my $self = shift;
	my @names = (ref($_[0]) eq 'ARRAY') ? @{ $_[0] } : @_; # <-- arg as array or arrayref
	return { map { $_ => $self->get_datapoint_value($_) } @names };
}


sub SchemaObj { (shift)->AuditObj->schema };
sub schema { ref (shift)->AuditObj->schema };
sub primary_key_separator { (shift)->AuditObj->primary_key_separator };
sub get_context_datapoints { (shift)->AuditObj->get_context_datapoints(@_) };
sub get_context_datapoint_names { (shift)->AuditObj->get_context_datapoint_names(@_) };
sub get_dt { (shift)->AuditObj->get_dt(@_) };

1;