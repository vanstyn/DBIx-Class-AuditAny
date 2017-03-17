package # hide from PAUSE 
    TestSchema::Three::Result::Team;
   
use base 'DBIx::Class::Core';
    
__PACKAGE__->table("team");
__PACKAGE__->add_columns(
  "id"			=> { data_type => "integer", is_auto_increment => 1, is_nullable => 0 },
  "name"			=> { data_type => "varchar", is_nullable => 0, size => 32 },
);
__PACKAGE__->set_primary_key("id");


__PACKAGE__->has_many(
  "players",
  "TestSchema::Three::Result::Player",
  { "foreign.team_id" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

1;
