package # Hide from PAUSE 
    DBIx::Class::AuditAny::Util::SchemaMaker;
use strict;
use warnings;

# VERSION
# ABSTRACT: Util package for on-the-fly creation of DBIC Schema classes

use Moo;
use MooX::Types::MooseLike::Base qw(:all);

#use Moose;
#use MooseX::Types::Moose qw(HashRef ArrayRef Str Bool Maybe Object CodeRef);

require Class::MOP::Class;
use DBIx::Class::AuditAny::Util;
use DBIx::Class::AuditAny::Util::ResultMaker;

has 'schema_namespace', is => 'ro', isa => Str, required => 1;
has 'class_opts', is => 'ro', isa => HashRef, default => sub {{}};
has 'results', is => 'ro', isa => HashRef[HashRef], required => 1;

sub initialize {
	my $self = shift;
	$self = $self->new(@_) unless (ref $self);
	
	my $class = $self->schema_namespace;
	die "class/namespace '$class' already defined!" if (package_exists $class);
	
	Class::MOP::Class->create($class,
		superclasses => [ 'DBIx::Class::Schema' ],
		%{ $self->class_opts }
	) or die $@;
	
	my @Results = sort keys %{$self->results};
	
	DBIx::Class::AuditAny::Util::ResultMaker->initialize(
		class_name => $class . '::' . $_,
		%{$self->results->{$_}}
	) for (@Results);
		
	$class->load_classes(@Results);
	
	return $class;
}

1;