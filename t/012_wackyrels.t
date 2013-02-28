# -*- perl -*-

use strict;
use warnings;
use Test::More;
use SQL::Translator 0.11016;

{
  package WackyRels::Parent;
  use base 'DBIx::Class::Core';
    
  __PACKAGE__->table("parent");
  __PACKAGE__->add_columns(
    "id"      => { data_type => "integer", is_auto_increment => 1, is_nullable => 0 },
    "color"   => { data_type => "char", is_nullable => 0, size => 32 },
    "size"    => { data_type => "char", is_nullable => 0, size => 32 },
    "info"    => { data_type => "varchar", is_nullable => 1, size => 255 },
  );
  __PACKAGE__->set_primary_key("id");
  __PACKAGE__->add_unique_constraint("color",["color","size"]);

  __PACKAGE__->has_many(
    "children",
    "WackyRels::Child",
    { 
      "foreign.color" => "self.color",
      "foreign.size" => "self.size",
    },
    { cascade_copy => 0, cascade_delete => 0 },
  );
};

{
  package WackyRels::Child;
  use base 'DBIx::Class::Core';
  
  __PACKAGE__->table("child");
  __PACKAGE__->add_columns(
    "color"   => { data_type => "char", is_nullable => 0, size => 32 },
    "size"    => { data_type => "char", is_nullable => 0, size => 32 },
    "info"    => { data_type => "varchar", is_nullable => 1, size => 255 },
  );
  __PACKAGE__->set_primary_key("color","size");

  __PACKAGE__->belongs_to(
    "parent",
    "WackyRels::Parent",
    { 
      "color" => "color",
      "size" => "size",
    },
    { is_deferrable => 1, on_delete => "CASCADE", on_update => "CASCADE" },
  );
};

{
  package WackyRels;
  use base qw/DBIx::Class::Schema/;
  __PACKAGE__->load_classes(qw/Parent Child/);
};

#########################


my $dsn = 'dbi:SQLite::memory:';

#my $db_file = '/tmp/wacky.db';
#unlink $db_file if (-f $db_file);
#$dsn = 'dbi:SQLite:dbname=' . $db_file;

my $schema = WackyRels->connect($dsn,'','', { 
  on_connect_call => 'use_foreign_keys' 
});

$schema->deploy;

$schema->resultset('Parent')->populate([
  [qw(color size info)],
  ['blue','big',"Big Blue Parent!"],
  ['blue','medium',"Medium Blue Parent!"],
]);

$schema->resultset('Child')->populate([
  [qw(color size info)],
  ['blue','big',"Big Blue Child 1!"],
]);

done_testing;
