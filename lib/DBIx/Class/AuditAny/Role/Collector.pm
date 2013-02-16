package DBIx::Class::AuditAny::Role::Collector;
use strict;
use warnings;

# VERSION
# ABSTRACT: Role for all Collector classes in DBIx::Class::AuditAny

use Moo::Role;
use MooX::Types::MooseLike::Base qw(:all);

requires 'record_changes';

has 'AuditObj', is => 'ro', required => 1;

# these are part of the base class because the AuditObj expects all
# Collectors to know if a particular tracked source is also a source used
# by the collector which would create a deep recursion situation
has 'writes_bound_schema_sources', is => 'ro', isa => ArrayRef[Str], lazy => 1, default => sub {[]};

# This is part of the "init" system for loading existing data. This is going
# to be refactored/replaced, but with what is not yet known
sub has_full_row_stored {
	my $self = shift;
	my $Row = shift;
	
	warn "has_full_row_stored() not implemented - returning false\n";
	
	return 0;
}

1;