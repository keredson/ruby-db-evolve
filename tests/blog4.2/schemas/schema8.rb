DB::Evolve::Schema.define do

  grant :insert, :update, :select, :delete

  create_table "blog2", :aka => "blog" do |t|
    t.string   "col1", :limit => 30
    t.string   "col2"
    t.string   "col2_1", :default => :something
    t.integer  "col3", :null => false, :default => 5
    t.decimal  "col4", :precision => 16, :scale => 4
    t.datetime "col5", :default => "infinity"
    t.datetime "col5_1", :default => "-infinity"
    t.datetime "col5_2", :default => "-Infinity"
    t.datetime "col6", :default => Float::INFINITY
    t.datetime "col7", :default => -Float::INFINITY
  end

end

