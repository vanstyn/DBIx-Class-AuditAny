package DBIx::Class::AuditAny::AuditContext::Column;
use strict;
use warnings;

# VERSION
# ABSTRACT: Default 'Column' context object class for DBIx::Class::AuditAny

use Moo;
use MooX::Types::MooseLike::Base qw(:all);
extends 'DBIx::Class::AuditAny::AuditContext';

#use Moose;
#use MooseX::Types::Moose qw(HashRef ArrayRef Str Bool Maybe Object CodeRef);



use DBIx::Class::AuditAny::Util;

has 'ChangeContext', is => 'ro', required => 1;
has 'column_name', is => 'ro', isa => Str, required => 1;
has 'old_value', is => 'ro', isa => Maybe[Str], required => 1;
has 'new_value', is => 'ro', isa => Maybe[Str], required => 1;

sub class { (shift)->ChangeContext->class }

sub _build_tiedContexts { 
	my $self = shift;
	my @Contexts = ( $self->ChangeContext, @{$self->ChangeContext->tiedContexts} );
	return \@Contexts;
}
sub _build_local_datapoint_data { 
	my $self = shift;
	return { map { $_->name => $_->get_value($self) } $self->get_context_datapoints('column') };
}


1;