package # hide from PAUSE
     Routine::AutoDBIC;
use strict;
use warnings;

use Test::Routine;

# This Role is expected to be composed with another role that already 
# composes 'Routine::Base'
#with 'Routine::Base';

use Test::More; 
use namespace::autoclean;

use String::Random;
sub get_rand_string { String::Random->new->randregex('[0-9A-Z]{10}') }

has 'auto_overwrite', is => 'ro', isa => 'Bool', default => 1;
has 'sqlite_db', is => 'ro', isa => 'Str', lazy => 1, default => sub {
	't/var/autodbic-' . get_rand_string . '.db';
};


before 'build_Auditor' => sub {
	my $self = shift;
	
	unlink $self->sqlite_db if (
		-f $self->sqlite_db and
		$self->auto_overwrite
	);
	
	die $self->sqlite_db . " already exists!"
		if (-e $self->sqlite_db);
	
	$self->track_params->{collector_class} ||= 'Collector::AutoDBIC';
	$self->track_params->{collector_params}
		->{sqlite_db} ||= $self->sqlite_db;
};



1;