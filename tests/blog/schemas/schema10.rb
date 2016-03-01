DB::Evolve::Schema.define do

  grant :insert, :update, :select, :delete
  revoke :update

  create_table "blog1" do |t|
    t.string   "col1"
    t.grant :trigger, :update
  end

  create_table "blog2" do |t|
    t.string   "col1"
    t.revoke :select
  end

  revoke :delete
  
  create_table "blog3" do |t|
    t.string   "col1"
    t.grant :update
  end

  create_table "blog4" do |t|
    t.string   "col1"
    t.grant :delete
  end

end

