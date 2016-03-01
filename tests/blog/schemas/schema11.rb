DB::Evolve::Schema.define do

  grant :insert, :update, :select, :delete
  revoke :update
  
  grant :insert, :update, to: "db_evolve_test2"

  create_table "blog1" do |t|
    t.string   "col1"
    t.grant :trigger, :update
  end

  create_table "blog2" do |t|
    t.string   "col1"
    t.revoke :select
    t.revoke :insert, from: "db_evolve_test2"
  end

  revoke :delete
  
  create_table "blog3" do |t|
    t.string   "col1"
    t.grant :update
    t.grant :select, to: "db_evolve_test2"
  end

  create_table "blog4" do |t|
    t.string   "col1"
    t.grant :delete
  end

end

