package # Hide from PAUSE 
     DBIx::Class::AuditAny::Collector::Code;
use strict;
use warnings;

# VERSION
# ABSTRACT: Coderef collector

use Moo;
use MooX::Types::MooseLike::Base qw(:all);
with 'DBIx::Class::AuditAny::Role::Collector';

has 'collect_coderef', is => 'ro', isa => CodeRef, required => 1;


sub record_changes {
	my $self = shift;
	return $self->collect_coderef->(@_);
}


1;