package # Hide from PAUSE 
     DBIx::Class::AuditAny::Util;

# VERSION
# ABSTRACT: Util functions for DBIx::Class::AuditAny

#*CORE::GLOBAL::die = sub { require Carp; Carp::confess };

require Exporter;
#use Term::ANSIColor qw(:constants);
use Data::Dumper;
require Module::Runtime;
use Try::Tiny;

our @ISA = qw(Exporter);
our @EXPORT = qw(resolve_localclass package_exists try catch uniq);

# debug util funcs
#
#sub scream {
#	local $_ = caller_data(3);
#	scream_color(YELLOW . BOLD,@_);
#}
#
#sub scream_color {
#	my $color = shift;
#	local $_ = caller_data(3) unless (
#		$_ eq 'no_caller_data' or (
#			ref($_) eq 'ARRAY' and
#			scalar(@$_) == 3 and
#			ref($_->[0]) eq 'HASH' and 
#			defined $_->[0]->{package}
#		)
#	);
#	
#	my $data = $_[0];
#	$data = \@_ if (scalar(@_) > 1);
#	$data = Dumper($data) if (ref $data);
#	$data = '  ' . UNDERLINE . 'undef' unless (defined $data);
#
#	my $pre = '';
#	$pre = BOLD . ($_->[2]->{subroutine} ? $_->[2]->{subroutine} . '  ' : '') .
#		'[line ' . $_->[1]->{line} . ']: ' . CLEAR . "\n" unless ($_ eq 'no_caller_data');
#	
#	print STDERR $pre . $color . $data . CLEAR . "\n";
#}
#
## Returns an arrayref of hashes containing standard 'caller' function data
## with named properties:
#sub caller_data {
#	my $depth = shift || 1;
#	
#	my @list = ();
#	for(my $i = 0; $i < $depth; $i++) {
#		my $h = {};
#		($h->{package}, $h->{filename}, $h->{line}, $h->{subroutine}, $h->{hasargs},
#			$h->{wantarray}, $h->{evaltext}, $h->{is_require}, $h->{hints}, $h->{bitmask}) = caller($i);
#		push @list,$h if($h->{package});
#	}
#	
#	return \@list;
#}

#unmht://www.develop-help.com.unmht/http.5/perl/examples/havepack.mhtml/
sub package_exists(@) {
	my ($pack) = @_;
	my $base ||= \%::;
	while ($pack =~ /(.*?)::(.*)/m	&& exists($base->{$1."::"})) {
		$base = *{$base->{$1."::"}}{HASH};
		$pack = $2;
	}
	return exists $base->{$pack."::"};
}

sub resolve_localclass($) { 
	my $class = shift;
	$class = $class =~ /^\+(.*)$/ ? $1 : "DBIx::Class::AuditAny::$class";
	Module::Runtime::require_module($class);
	return $class;
}

# uniq() util func:
# Returns a list with duplicates removed. If passed a single arrayref, duplicates are
# removed from the arrayref in place, and the new list (contents) are returned.
sub uniq {
	my %seen = ();
	return grep { !$seen{$_}++ } @_ unless (@_ == 1 and ref($_[0]) eq 'ARRAY');
	return () unless (@{$_[0]} > 0);
	# we add the first element to the end of the arg list to prevetn deep recursion in the
	# case of nested single element arrayrefs
	@{$_[0]} = uniq(@{$_[0]},$_[0]->[0]);
	return @{$_[0]};
}


1;