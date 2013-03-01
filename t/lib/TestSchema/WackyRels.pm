package # hide from PAUSE 
    TestSchema::WackyRels;
    
use base qw/DBIx::Class::Schema/;


{
  package TestSchema::WackyRels::Parent;
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
    "TestSchema::WackyRels::Child",
    { 
      "foreign.color" => "self.color",
      "foreign.size" => "self.size",
    },
    { cascade_copy => 0, cascade_delete => 0 },
  );
};

{
  package TestSchema::WackyRels::Child;
  use base 'DBIx::Class::Core';
  
  __PACKAGE__->table("child");
  __PACKAGE__->add_columns(
    "id"      => { data_type => "integer", is_auto_increment => 1, is_nullable => 0 },
    "color"   => { data_type => "char", is_nullable => 0, size => 32 },
    "size"    => { data_type => "char", is_nullable => 0, size => 32 },
    "info"    => { data_type => "varchar", is_nullable => 1, size => 255 },
  );
  __PACKAGE__->set_primary_key("id");

  __PACKAGE__->belongs_to(
    "parent",
    "TestSchema::WackyRels::Parent",
    { 
      "color" => "color",
      "size" => "size",
    },
    { is_deferrable => 1, on_delete => "CASCADE", on_update => "CASCADE" },
  );
};



__PACKAGE__->load_classes(qw/Parent Child/);

1;
