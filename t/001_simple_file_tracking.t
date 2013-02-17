# -*- perl -*-

# t/001_simple_file_tracking.t - test logging changes to a file

use strict;
use warnings;
use lib qw(t/lib);
use Test::Routine::Util;
use Test::More;

mkdir('t/var') unless (-d 't/var');
my $log = 't/var/log.txt';
unlink $log if (-f $log);


run_tests('Tracking to a file' => 'Routine::One' => {
	track_params => { 
		track_immutable => 1,
		track_all_sources => 1,
		collect => sub {
			# Notice this simple collector is *not* pulling any data via
			# datapoints. Datapoints are optional sugar that are only
			# pulled when called from a -Collector-
			my $ChangeSet = shift;
			open LOG, ">> $log" or die $!;
			print LOG join("\t",
				$_->ChangeContext->action,
				$_->column_name,
				$_->old_value || '<undef>',
				$_->new_value || '<undef>'
			) . "\n" for ($ChangeSet->all_column_changes);
			close LOG;
		}
	}
});





my $d = {};
ok(open(LOG, "< $log"), "Open the log file for reading");
while(<LOG>) {
	chomp $_;
	my @cols = split(/\t/,$_,4);
	$d->{$cols[0]}->{$cols[1]} = { 
		old => $cols[2], 
		new => $cols[3]
	}
}
close LOG;

ok(
	(
		$d->{insert}->{first}->{new} eq 'John' and
		$d->{insert}->{last}->{new} eq 'Smith'
	), 
	"Log contains expected INSERT entries"
);

ok(
	(
		$d->{update}->{last}->{old} eq 'Smith' and
		$d->{update}->{last}->{new} eq 'Doe'
	), 
	"Log contains expected UPDATE entries"
);

ok(
	(
		$d->{delete}->{first}->{old} eq 'John' and
		$d->{delete}->{last}->{old} eq 'Doe'
	), 
	"Log contains expected DELETE entries"
);


done_testing;
