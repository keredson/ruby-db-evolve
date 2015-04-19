DB::Evolve::Schema.define do

  create_table "blog" do |t|
    t.string   "col1"
    t.string   "col2", :null => false
    t.integer   "col3"
    t.text   "col4"
  end

end
