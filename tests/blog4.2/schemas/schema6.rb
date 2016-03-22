DB::Evolve::Schema.define do

  create_table "blog2", :aka => "blog" do |t|
    t.string   "col1", :limit => 30
    t.string   "col2"
    t.integer  "col3", :null => false, :default => 5
    t.decimal  "col4", :precision => 16, :scale => 4
    t.datetime "col5"
  end

end

