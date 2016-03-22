DB::Evolve::Schema.define do

  create_table "blog2", :aka => "blog" do |t|
    t.string   "col1"
    t.string   "col2", :null => false
    t.integer   "col3", :aka => "col5"
  end

end

