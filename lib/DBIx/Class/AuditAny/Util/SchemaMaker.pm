package # Hide from PAUSE 
    DBIx::Class::AuditAny::Util::SchemaMaker;

# VERSION

use Moose;
require Class::MOP::Class;
use DBIx::Class::AuditAny::Util;
use DBIx::Class::AuditAny::Util::ResultMaker;

has 'schema_namespace', is => 'ro', isa => 'Str', required => 1;
has 'class_opts', is => 'ro', isa => 'HashRef', default => sub {{}};
has 'results', is => 'ro', isa => 'HashRef[HashRef]', required => 1;

sub initialize {
	my $self = shift;
	
	my $class = $self->schema_namespace;
	die "class/namespace '$class' already defined!" if (package_exists $class);
	
	Class::MOP::Class->create($class,
		superclasses => [ 'DBIx::Class::Schema' ],
		%{ $self->class_opts }
	) or die $@;
	
	my @Results = sort keys %{$self->results};
	
	DBIx::Class::AuditAny::Util::ResultMaker->new(
		class_name => $class . '::' . $_,
		%{$self->results->{$_}}
	)->initialize for (@Results);
		
	$class->load_classes(@Results);
	
	return $class;
}

1;