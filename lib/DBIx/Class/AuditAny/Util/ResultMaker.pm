package # Hide from PAUSE 
    DBIx::Class::AuditAny::Util::ResultMaker;
use strict;
use warnings;

# VERSION
# ABSTRACT: Util package for on-the-fly creation of DBIC Result classes

use Moo;
use MooX::Types::MooseLike::Base qw(:all);

#use Moose;
#use MooseX::Types::Moose qw(HashRef ArrayRef Str Bool Maybe Object CodeRef);

require Class::MOP::Class;
use DBIx::Class::AuditAny::Util;

has 'class_name', 			is => 'ro', isa => Str, required => 1;
has 'class_opts', 			is => 'ro', isa => HashRef, default => sub {{}};
has 'table_name', 			is => 'ro', isa => Str, required => 1;
has 'columns', 				is => 'ro', isa => ArrayRef, required => 1;
has 'call_class_methods',	is => 'ro', isa => ArrayRef, default => sub {[]};

sub initialize {
	my $self = shift;
	$self = $self->new(@_) unless (ref $self);
	
	my $class = $self->class_name;
	die "class/namespace '$class' already defined!" if (package_exists $class);
	
	Class::MOP::Class->create($class,
		superclasses => [ 'DBIx::Class::Core' ],
		%{ $self->class_opts }
	) or die $@;
	
	$class->table( $self->table_name );
	
	$class->add_columns( @{$self->columns} );
	
	my @call_list = @{$self->call_class_methods};
	while (my $meth = shift @call_list) {
		my $args = shift @call_list;
		$class->$meth(@$args);
	}

	return $class;
}

1;