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
  task :evolve, [:arg1,:arg2] => :environment do |t, args|
  
    argv = [ args[:arg1], args[:arg2] ] 
    noop = argv.include? "noop"
    nowait = argv.include? "nowait"
    yes = argv.include? "yes"
  
    # confirm our shim is in place before we load schema.rb
    # lest we accidentally drop and reload their database!
    ActiveRecord::Schema.iloaded 

    do_evolve(noop, yes, nowait)

  end

  # mock db:schema:load db:test:load so "rake spec" works
  namespace :test do
    task :load do
      # do nothing
    end
  end
  namespace :schema do
    task :load do
      do_evolve(false, true, true)
    end
  end

end


def do_evolve(noop, yes, nowait)
  existing_tables, existing_indexes = load_existing_tables()

  require_relative 'db_mock'

  require Rails.root + 'db/schema'

  adds, deletes, renames = calc_table_changes(existing_tables.keys, $schema_tables.keys, $akas_tables)

  to_run = []

  to_run += sql_adds(adds)
  to_run += sql_renames(renames)

  rename_cols_by_table = {}

  existing_tables.each do |etn, ecols|
    next if deletes.include? etn
    ntn = renames[etn] || etn
    commands, rename_cols = calc_column_changes(ntn, existing_tables[etn], $schema_tables[ntn].columns)
    to_run += commands
    rename_cols_by_table[ntn] = rename_cols
  end
  
  to_run += calc_index_changes(existing_indexes, $schema_indexes, renames, rename_cols_by_table)

  to_run += sql_drops(deletes)

  # prompt and execute
  
  if to_run.empty?
    if !noop
      puts "\nYour database is up to date!"
      puts
    end
  else
    to_run.unshift("\nBEGIN TRANSACTION")
    to_run.append("\nCOMMIT")

    require_relative 'sql_color'
    to_run.each do |sql|
      puts SQLColor.colorize(sql)
    end
    puts

    if noop
      return
    end

    config = ActiveRecord::Base.connection_config
    puts "Connecting to database:"
    config.each do |k,v|
      next if k==:password
      puts "\t#{k} => #{v}"
    end
    
    if !yes
      print "Run this SQL? (type yes or no) "
    end
    if yes || STDIN.gets.strip=='yes'
      require 'pg'
      config = ActiveRecord::Base.connection_config
      config.delete(:adapter)
      config[:dbname] = config.delete(:database)
      config[:user] = config.delete(:username)
      if !nowait
        print "\nExecuting in "
        [3,2,1].each do |c|
          print "#{c}..."
          sleep(1)
        end
      end
      puts
      conn = PG::Connection.open(config)
      to_run.each do |sql|
        puts SQLColor.colorize(sql)
        conn.exec(sql)
      end
      puts "\n--==[ COMPLETED ]==--"
    else
      puts "\n--==[ ABORTED ]==--"
    end
    puts
  end


end


def calc_index_changes(existing_indexes, schema_indexes, table_renames, rename_cols_by_table)
  # rename_cols_by_table is by the new table name
  existing_indexes = Set.new existing_indexes
  schema_indexes = Set.new schema_indexes
  
  add_indexes = schema_indexes - existing_indexes
  delete_indexes = existing_indexes - schema_indexes

  $tmp_to_run = []  

  connection = ActiveRecord::Base.connection

  add_indexes.each do |index|
    table = index.delete(:table)
    columns = index.delete(:columns)
    connection.add_index table, columns, index
  end
  
  to_run = $tmp_to_run

  delete_indexes.each do |index|
    $tmp_to_run = []
    table = index.delete(:table)
    name = index[:name]
    connection.remove_index table, :name => name
    to_run.append($tmp_to_run[0].sub('DROP INDEX', 'DROP INDEX IF EXISTS'))
  end

  if !to_run.empty?
    to_run.unshift("\n-- update indexes")
  end
  
  return to_run
end



IgnoreTables = Set.new ["schema_migrations"]

def load_existing_tables()
  existing_tables = {}
  existing_indexes = []
  connection = ActiveRecord::Base.connection
  connection.tables.sort.each do |tbl|
    next if IgnoreTables.include? tbl
    columns = connection.columns(tbl)
    existing_tables[tbl] = columns
    connection.indexes(tbl).each do |i|
      index = {:table => i.table, :name => i.name, :columns => i.columns, :unique => i.unique}
      existing_indexes.append(index)
    end
  end
  return existing_tables, existing_indexes
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
      c.opts[:default] = normalize_default(c.opts[:default]) if c.opts[:default].present?
      c.default = c.opts[:default]
      c.null = c.opts[:null]
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
    c.opts = { :null=>false }
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

$schema_indexes = []

def add_index(table, columns, opts)
  opts[:table] = table
  opts[:columns] = columns
  if !opts.has_key? :unique
    opts[:unique] = false
  end
  $schema_indexes.append(opts)
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
  return PG::Connection.quote_ident k
end

def gen_pg_adapter()
  $tmp_to_run = []
  a = ActiveRecord::ConnectionAdapters::PostgreSQLAdapter.allocate
  ActiveRecord::ConnectionAdapters::AbstractAdapter.instance_method(:initialize).bind(a).call ActiveRecord::Base.connection
  return a
end

def sql_renames(renames)
  to_run = []
  pg_a = gen_pg_adapter()
  renames.each do |k,v|
    pg_a.rename_table(k, v)
    to_run += $tmp_to_run
  end
  if !to_run.empty?
    to_run.unshift("\n-- rename tables")
  end
  return to_run
end

def sql_drops(tables)
  to_run = []
  tables.each do |tbl|
    sql = "DROP TABLE #{escape_table(tbl)}"
    to_run.append sql
  end
  if !to_run.empty?
    to_run.unshift("\n-- remove tables")
  end
  return to_run
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

# taken from comments in ActiveRecord::ConnectionAdapters::TableDefinition
NATIVE_DATABASE_PRECISION = {
  :numeric => 19,
  :decimal => 19, #38,
}
NATIVE_DATABASE_SCALE = {
}

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
      pg_a.add_column(tbl, cn, sc.type.to_sym, sc.opts)
    end
    to_run += $tmp_to_run
  end
  
  $tmp_to_run = []
  rename_cols.each do |ecn, scn|
    pg_a.rename_column(tbl, ecn, scn)
  end
  to_run += $tmp_to_run
  delete_cols.each do |cn|
    to_run.append("ALTER TABLE #{escape_table(tbl)} DROP COLUMN #{escape_table(cn)}")
  end
  
  same_names = existing_col_names - delete_cols
  same_names.each do |ecn|
    $tmp_to_run = []
    ec = existing_cols_by_name[ecn]
    if rename_cols.include? ecn
      sc = schema_cols_by_name[rename_cols[ecn]]
    else
      sc = schema_cols_by_name[ecn]
    end
    type_changed = sc.type.to_s != ec.type.to_s
    # numeric and decimal are equiv in postges, and the db always returns numeric
    if type_changed and sc.type.to_s=="decimal" and ec.type.to_s=="numeric"
      type_changed = false
    end
    # ruby turns decimal(x,0) into integer when reading meta-data
    if type_changed and sc.type.to_s=="decimal" and ec.type.to_s=="integer" and sc.opts[:scale]==0
      type_changed = false
    end
    sc_limit = sc.opts.has_key?(:limit) ? sc.opts[:limit] : ActiveRecord::ConnectionAdapters::PostgreSQLAdapter::NATIVE_DATABASE_TYPES[sc.type.to_sym][:limit]
    limit_changed = (sc.type=="string" and sc_limit!=ec.limit) # numeric types in postgres report the precision as the limit - ignore non string types for now
    sc_precision = sc.opts.has_key?(:precision) ? sc.opts[:precision] : NATIVE_DATABASE_PRECISION[sc.type]
    precision_changed = (sc.type=="decimal" and sc_precision!=ec.precision) # by type_to_sql in schema_statements.rb, precision is only used on decimal types
    sc_scale = sc.opts.has_key?(:scale) ? sc.opts[:scale] : NATIVE_DATABASE_SCALE[sc.type]
    scale_changed = (sc.type=="decimal" and sc_scale!=ec.scale)
    if type_changed or limit_changed or precision_changed or scale_changed
      pg_a.change_column(tbl, sc.name, sc.type.to_sym, sc.opts)
    end
    if normalize_default(ec.default) != sc.opts[:default]
      pg_a.change_column_default(tbl, sc.name, sc.opts[:default])
    end
    sc_null = sc.opts.has_key?(:null) ? sc.opts[:null] : true
    if ec.null != sc_null
      if !sc_null and !sc.opts.has_key?(:default)
        raise "\nERROR: In order to set #{tbl}.#{sc.name} as NOT NULL you need to add a :default value.\n\n"
      end
      pg_a.change_column_null(tbl, sc.name, sc_null, sc.opts[:default])
    end
    to_run += $tmp_to_run
  end

  if !to_run.empty?
    to_run.unshift("\n-- column changes for table #{tbl}")
  end
  
  return to_run, rename_cols
end

def normalize_default default
  default = default.to_s if default.is_a? Symbol
  if (default.respond_to?(:infinite?) && default.infinite?) || default.is_a?(String) && (default.downcase == 'infinity' || default.downcase == '-infinity')
    default = default.to_s.downcase
  end
  return default
end


$tmp_to_run = []

