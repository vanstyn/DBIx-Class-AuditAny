# -*- perl -*-

# t/001_simple_file_tracking.t - test logging changes to a file

use strict;
use warnings;
use Test::More;
use DBICx::TestDatabase 0.04;
use lib qw(t/lib);

plan tests => 11;

use_ok( 'DBIx::Class::AuditAny' );

ok(
	my $schema = DBICx::TestDatabase->new('TestSchema::One'),
	"Initialize Test Database"
);

mkdir('t/var') unless (-d 't/var');
my $log = 't/var/log.txt';

ok(
	DBIx::Class::AuditAny->track(
		schema => $schema, 
		track_immutable => 1,
		track_all_sources => 1,
		collect => sub {
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
	),
	"Setup simple tracker configured to write to text file"
);

ok( 
	$schema->resultset('Contact')->create({
		first => 'John', 
		last => 'Smith' 
	}),
	"Insert a test row"
);

ok(
	my $Row = $schema->resultset('Contact')->search_rs({ last => 'Smith' })->first,
	"Find the test row"
);

ok(
	$Row->update({ last => 'Doe' }),
	"Update the test row"
);

ok(
	$Row->delete,
	"Delete the test row"
);

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
