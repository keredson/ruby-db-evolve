DB::Evolve::Schema.define do

  create_table "blog" do |t|
    t.string   "col1"
    t.string   "col2", :null => false
  end

end
