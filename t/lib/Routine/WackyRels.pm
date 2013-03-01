package # hide from PAUSE
     Routine::WackyRels;
use strict;
use warnings;

use Test::Routine;
with 'Routine::Base';

use Test::More; 
use namespace::autoclean;

has 'test_schema_class', is => 'ro', default => 'TestSchema::WackyRels';

test 'inserts' => { desc => 'Insert Test Data' } => sub {
  my $self = shift;
  my $schema = $self->Schema;
  
  
  $schema->txn_do(sub {
    ok(
      # Remove $ret to force VOID context (needed to test Storgae::insert_bulk codepath)
      do { my $ret = $schema->resultset('Parent')->populate([
        [qw(color size info)],
        ['blue','big',"Big Blue Parent!"],
        ['blue','medium',"Medium Blue Parent!"]
      ]); 1; },
      "Populate Some Parent rows"
    );
  });
  
  $schema->txn_do(sub {
    ok(
      # Remove $ret to force VOID context (needed to test Storgae::insert_bulk codepath)
      do { my $ret = $schema->resultset('Child')->populate([
        [qw(color size info)],
        ['blue','big',"First child"],
        ['blue','big',"Second child"],
        ['blue','big',"Third child"],
        ['blue','medium',"alpha"],
        ['blue','medium',"bravo"]
      ]); 1; },
      "Populate Some Child rows"
    );
  });
  
};


test 'updates_cascades' => { desc => 'Updates causing db-side cascades' } => sub {
  my $self = shift;
  my $schema = $self->Schema;
  
  ok(
    my $Parent = $schema->resultset('Parent')->search_rs({ 
      size => 'big',
      color => 'blue'
    })->first,
    "Find 'big-blue' Parent row"
  );
  
  ok(
    $Parent->update({ color => 'red' }),
    "Change the PK of the 'big-blue' Parent row row (should cascade)"
  );
  
};	

1;