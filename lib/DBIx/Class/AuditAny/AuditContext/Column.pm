package DBIx::Class::AuditAny::AuditContext::Column;
use strict;
use warnings;

# ABSTRACT: Default 'Column' context object class for DBIx::Class::AuditAny

=head1 NAME

DBIx::Class::AuditAny::AuditContext::Column - Default 'Column' context object for DBIx::Class::AuditAny

=head1 DESCRIPTION

This class tracks a single change to a single column, belonging to a parent "Change" context which 
represents multiple column changes, and the Change may belong to a "ChangeSet" which may comprise 
multiple different Changes, which of which having 1 or more column change contexts.

=cut

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

__END__
=head1 SUPPORT
 
IRC:
 
    Join #rapidapp on irc.perl.org.

=head1 AUTHOR

Henry Van Styn <vanstyn@cpan.org>

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2012 by IntelliTree Solutions llc.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=cut