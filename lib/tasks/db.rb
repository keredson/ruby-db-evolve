require 'set'
require 'active_record'
require 'active_support/all'

module ActiveRecord
  class Migration
    def iloaded()
    end
  end
  class Schema
    def self.define(x)
      raise "\nTo use rails-db-evolve, please edit your schema.db file and change:\n\n  ActiveRecord::Schema.define(...) do\n\nto:\n\n  DB::Schema.define do\n\nAnd re-run this task.\n\n"
    end
  end
end


namespace :db do

  desc "Diff your database against your schema.rb and offer SQL to bring your database up to date."
  task :evolve => :environment do
  
    # confirm our shim is in place before we load schema.rb
    # lest we accidentally drop and reload their database!
    ActiveRecord::Schema.iloaded 

    do_evolve()

  end

end


def do_evolve()
  existing_tables = load_existing_tables()

  require_relative 'db_mock'

  require Rails.root + 'db/schema'


  adds, deletes, renames = calc_table_changes(existing_tables.keys, $schema_tables.keys, $akas_tables)

  to_run = []

  to_run += sql_adds(adds)
  to_run += sql_renames(renames)

  existing_tables.each do |etn, ecols|
    next if deletes.include? etn
    ntn = renames[etn] || etn
    to_run += calc_column_changes(ntn, existing_tables[etn], $schema_tables[ntn].columns)
  end

  to_run += sql_drops(deletes)

  if to_run.empty?
    puts "\nYour database is up to date!"
    puts
  else
    to_run.unshift("\nBEGIN TRANSACTION;")
    to_run.append("\nCOMMIT;")

    puts to_run.join("\n")
    puts

    config = ActiveRecord::Base.connection_config
    puts "Connecting to database:"
    config.each do |k,v|
      next if k==:password
      puts "\t#{k} => #{v}"
    end
    print "Run this SQL? (type yes or no) "
    if STDIN.gets.strip=='yes'
      require 'pg'
      config = ActiveRecord::Base.connection_config
      config.delete(:adapter)
      config[:dbname] = config.delete(:database)
      config[:user] = config.delete(:username)
      print "\nExecuting in "
      [5,4,3,2,1].each do |c|
        print "#{c}..."
        sleep(1)
      end
      puts
      conn = PG::Connection.open(config)
      to_run.each do |sql|
        puts sql
        conn.exec(sql)
      end
      puts "\n--==[ COMPLETED ]==--"
    else
      puts "\n--==[ ABORTED ]==--"
    end
    puts
  end


end





IgnoreTables = Set.new ["schema_migrations"]

def load_existing_tables()
  existing_tables = {}
  connection = ActiveRecord::Base.connection
  connection.tables.sort.each do |tbl|
    next if IgnoreTables.include? tbl
    columns = connection.columns(tbl)
    existing_tables[tbl] = columns
  end
  return existing_tables
end




class Table
  attr_accessor :name, :opts, :id, :columns
  
  def initialize()
    @columns = []
  end
  
  def method_missing(method_sym, *arguments, &block)
    c = Column.new
    c.type = method_sym.to_s
    c.name = arguments[0]
    c.opts = arguments[1]
    if c.opts
      c.default = c.opts["default"]
      c.default = c.opts["null"]
      aka = c.opts[:aka]
      if !aka.nil?
        if aka.respond_to?('each')
          c.akas = aka
        else
          c.akas = [aka]
        end
      end
    else
      c.opts = {}
    end
    @columns.append c
  end 
   
end

class Column
  attr_accessor :name, :type, :opts, :null, :default, :akas
end

$schema_tables = {}
$akas_tables = Hash.new { |h, k| h[k] = Set.new }

def create_table(name, opts={})
  tbl = Table.new
  tbl.name = name
  tbl.opts = opts
  if opts
    if opts.has_key? 'id'
      tbl.id = opts['id']
    else
      tbl.id = true
    end
  end
  if tbl.id
    c = Column.new
    c.type = "integer"
    c.name = "id"
    c.opts = {}
    tbl.columns.append c
  end
  yield tbl
  $schema_tables[name] = tbl
  aka = tbl.opts[:aka]
  if !aka.nil?
    if aka.respond_to?('each')
      $akas_tables[tbl.name].merge(aka)
    else
      $akas_tables[tbl.name].add(aka)
    end
  end
end

def add_index(name, columns, opts)
#  puts 'add_index'
end

module DB
  module Evolve
    class Schema
      def self.define()
        yield
      end
    end
  end
end

def calc_table_changes(existing_tables, schema_tables, akas_tables)
  existing_tables = Set.new existing_tables
  schema_tables = Set.new schema_tables
  adds = schema_tables - existing_tables
  deletes = existing_tables - schema_tables
  renames = {}
  adds.each do |newt|
    akas = Set.new akas_tables[newt]
    possibles = akas & deletes
    if possibles.size > 1
      raise "Too many possible table matches (#{possibles}) for #{newt}.  Please trim your akas."
    end
    if possibles.size == 1
      oldt = possibles.to_a()[0]
      renames[oldt] = newt
      adds.delete(newt)
      deletes.delete(oldt)
    end
  end
  return adds, deletes, renames
end

def escape_table(k)
  return "\"#{k}\""
end

def sql_renames(renames)
  to_run = []
  renames.each do |k,v|
    sql = "ALTER TABLE #{escape_table(k)} RENAME TO #{escape_table(v)};"
    to_run.append sql
  end
  if !to_run.empty?
    to_run.unshift("\n-- rename tables")
  end
  return to_run
end

def sql_drops(tables)
  to_run = []
  tables.each do |tbl|
    sql = "DROP TABLE #{escape_table(tbl)};"
    to_run.append sql
  end
  if !to_run.empty?
    to_run.unshift("\n-- remove tables")
  end
  return to_run
end

def gen_pg_adapter()
  $tmp_to_run = []
  a = ActiveRecord::ConnectionAdapters::PostgreSQLAdapter.allocate
  ActiveRecord::ConnectionAdapters::AbstractAdapter.instance_method(:initialize).bind(a).call ActiveRecord::Base.connection
  return a
end

def sql_adds(tables)
  a = gen_pg_adapter()
  tables.each do |tn|
    tbl = $schema_tables[tn]
    a.create_table tbl.name, :force => true do |t|
      tbl.columns.each do |c|
        t.send(c.type.to_sym, *[c.name, c.opts])
      end
    end
  end
  if !$tmp_to_run.empty?
    $tmp_to_run.unshift("\n-- add tables")
  end
  return $tmp_to_run
end

def can_convert(type1, type2)
  if type1==type2
    return true
  end
  if type1=='integer' and type2=='decimal'
    return true
  end
  return false
end

def calc_column_changes(tbl, existing_cols, schema_cols)

  existing_cols_by_name = Hash[existing_cols.collect { |c| [c.name, c] }]
  schema_cols_by_name = Hash[schema_cols.collect { |c| [c.name, c] }]
  existing_col_names = Set.new existing_cols_by_name.keys
  schema_col_names = Set.new schema_cols_by_name.keys
  new_cols = schema_col_names - existing_col_names
  delete_cols = existing_col_names - schema_col_names
  rename_cols = {}
  
  new_cols.each do |cn|
    sc = schema_cols_by_name[cn]
    if sc.akas
      sc.akas.each do |aka|
        if delete_cols.include? aka
          ec = existing_cols_by_name[aka]
          if can_convert(sc.type.to_s, ec.type.to_s)
            rename_cols[ec.name] = sc.name
            new_cols.delete cn
            delete_cols.delete aka
          end
        end
      end
    end
  end
  
  to_run = []

  pg_a = gen_pg_adapter()

  if new_cols.size > 0
#    puts "tbl: #{tbl} new_cols: #{new_cols}"
    new_cols.each do |cn|
      sc = schema_cols_by_name[cn]
      pg_a.add_column(tbl, cn, sc.type, sc.opts)
    end
    to_run += $tmp_to_run
  end
  
  rename_cols.each do |ecn, scn|
    to_run.append("ALTER TABLE #{escape_table(tbl)} RENAME COLUMN #{escape_table(ecn)} TO #{escape_table(scn)};")
  end
  delete_cols.each do |cn|
    to_run.append("ALTER TABLE #{escape_table(tbl)} DROP COLUMN #{escape_table(cn)}")
  end
  
  same_names = existing_col_names - delete_cols
  same_names.each do |ecn|
    ec = existing_cols_by_name[ecn]
    if rename_cols.include? ecn
      sc = schema_cols_by_name[rename_cols[ecn]]
    else
      sc = schema_cols_by_name[ecn]
    end
    if sc.type.to_s != ec.type.to_s
      type = pg_a.type_to_sql(sc.type, sc.opts[:limit], sc.opts[:precision], sc.opts[:scale])
      to_run.append("ALTER TABLE #{escape_table(tbl)} ALTER COLUMN #{escape_table(sc.name)} TYPE #{type}") # using the_column::bigint
    end
  end

  if !to_run.empty?
    to_run.unshift("\n-- column changes for table #{tbl}")
  end
  
  return to_run
end



$tmp_to_run = []






