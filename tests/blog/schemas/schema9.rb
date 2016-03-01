DB::Evolve::Schema.define do

  grant :insert, :update, :select, :delete

  create_table "blog1" do |t|
    t.string   "col1"
  end

  create_table "blog2" do |t|
    t.string   "col1"
  end

  create_table "blog3" do |t|
    t.string   "col1"
  end

  create_table "blog4" do |t|
    t.string   "col1"
  end

end

