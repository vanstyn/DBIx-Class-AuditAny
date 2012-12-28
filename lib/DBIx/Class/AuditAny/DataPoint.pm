package DBIx::Class::AuditAny::DataPoint;
use Moose;

# VERSION
# ABSTRACT: Object class for AuditAny datapoint configs

use Switch qw(switch);

has 'AuditObj', is => 'ro', isa => 'DBIx::Class::AuditAny', required => 1;
has 'name', is => 'ro', isa => 'Str', required => 1;
has 'context', is => 'ro', isa => 'Str', required => 1;
has 'method', is => 'ro', isa => 'Str|CodeRef', required => 1;
has 'user_defined', is => 'ro', isa => 'Bool', default => 0;

# Optional extra attr to keep track of a separate 'original' name. Auto
# set when 'rename_datapoints' are specified (see top DBIx::Class::AuditAny class)
has 'original_name', is => 'ro', isa => 'Str', lazy => 1, 
 default => sub { (shift)->name };

# -- column_info defines the schema needed to store this datapoint within
# a DBIC Result/table. Only used in collectors like Collector::AutoDBIC
has 'column_info', is => 'ro', isa => 'HashRef', lazy => 1, 
 default => sub { my $self = shift; $self->get_column_info->($self) };
 
has 'get_column_info', is => 'ro', isa => 'CodeRef', lazy => 1,
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