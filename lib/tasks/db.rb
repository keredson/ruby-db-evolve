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


$i_nagged = false

$db_username = HashWithIndifferentAccess.new(Rails.configuration.database_configuration[Rails.env])[:username] || ENV['USER'] || ENV['USERNAME']

def get_connection_config
  config_name = "#{Rails.env}_dbevolve"
  if Rails.configuration.database_configuration[config_name].present?
    config = Rails.configuration.database_configuration[config_name]
  else
    unless $i_nagged || Rails.env=='development'
      puts "Your database.yml file does not contain an entry for '#{config_name}', so we're using '#{Rails.env}'.  This works if your database user has permission to edit your schema, but this is not recommended outside of development.  For more information visit: https://github.com/keredson/ruby-db-evolve/blob/master/README.md#schema-change-permissions"
      $i_nagged = true
    end
    config = Rails.configuration.database_configuration[Rails.env]
  end
  return config
end

def build_pg_connection_config
  config = HashWithIndifferentAccess.new get_connection_config
  config.delete(:adapter)
  config.delete(:pool)
  config[:dbname] = config.delete(:database)
  config[:user] = config.delete(:username) || ENV['USER'] || ENV['USERNAME']
  return config
end

def build_pg_connection
  return PG::Connection.open(build_pg_connection_config)
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

  to_run += calc_fk_changes($foreign_keys, Set.new(existing_tables.keys), renames)

  to_run += calc_perms_changes($schema_tables, noop) unless $check_perms_for.empty?

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

    puts "Connecting to database:"
    build_pg_connection_config.each do |k,v|
      v = "*" * v.length if k.present? && k.to_s=='password'
      puts "\t#{k} => #{v}"
    end
    
    if !yes
      print "Run this SQL? (type yes or no) "
    end
    if yes || STDIN.gets.strip=='yes'
      if !nowait
        print "\nExecuting in "
        [3,2,1].each do |c|
          print "#{c}..."
          sleep(1)
        end
      end
      puts
      conn = build_pg_connection
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
  existing_indexes.each do |index|
    if table_renames[index[:table]].present?
      index[:table] = table_renames[index[:table]]
    end
  end
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
    table = index.delete(:table)
    name = index[:name]
    to_run << "DROP INDEX IF EXISTS #{escape_table(name)}"
  end

  if !to_run.empty?
    to_run.unshift("\n-- update indexes")
  end
  
  return to_run
end

def calc_fk_changes(foreign_keys, existing_tables, renames)
  existing_foreign_keys = []
  unless existing_tables.empty?
    existing_tables_sql = (existing_tables.map {|tn| ActiveRecord::Base.sanitize(tn)}).join(',')
    sql = %{
      SELECT
          tc.constraint_name, tc.table_name, kcu.column_name, 
          ccu.table_name AS foreign_table_name,
          ccu.column_name AS foreign_column_name 
      FROM 
          information_schema.table_constraints AS tc 
          JOIN information_schema.key_column_usage AS kcu
            ON tc.constraint_name = kcu.constraint_name
          JOIN information_schema.constraint_column_usage AS ccu
            ON ccu.constraint_name = tc.constraint_name
      WHERE constraint_type = 'FOREIGN KEY'
        AND tc.table_name in (#{existing_tables_sql});
    }
    build_pg_connection.exec(sql).each do |row|
      from_table = row['table_name']
      from_table = renames[from_table] if renames[from_table].present?
      to_table = row['foreign_table_name']
      to_table = renames[to_table] if renames[to_table].present?
      existing_foreign_keys << HashWithIndifferentAccess.new({
        :from_table => from_table,
        :to_table => to_table,
        :column => row['column_name'],
        :primary_key => row['foreign_column_name'],
        :name => row['constraint_name'],
      })
    end
  end

  existing_foreign_keys = Set.new existing_foreign_keys
  foreign_keys = Set.new foreign_keys
  add_fks = foreign_keys - existing_foreign_keys
  delete_fks = existing_foreign_keys - foreign_keys
  
  rename_fks = []
  delete_fks.each do |delete_fk|
    dfk = delete_fk.clone
    dfk.delete(:name)
    add_fks.each do |add_fk|
      afk = add_fk.clone
      afk.delete(:name)
      if afk==dfk
        delete_fks.delete delete_fk
        add_fks.delete add_fk
        rename_fks << {
          :table => delete_fk[:from_table],
          :from_name => delete_fk[:name],
          :to_name => add_fk[:name]
        }
        # ALTER TABLE name RENAME CONSTRAINT "error_test_id_fkey" TO "the_new_name_fkey";
      end
    end
  end

  to_run = []
  delete_fks.each do |fk|
    to_run << "ALTER TABLE #{escape_table(fk[:from_table])} DROP CONSTRAINT IF EXISTS #{escape_table(fk[:name])}"
  end
  add_fks.each do |fk|
    to_run << "ALTER TABLE #{escape_table(fk[:from_table])} ADD CONSTRAINT #{escape_table(fk[:name])} FOREIGN KEY (#{escape_table(fk[:column])}) REFERENCES #{escape_table(fk[:to_table])} (#{escape_table(fk[:primary_key])}) MATCH FULL"
  end
  rename_fks.each do |fk|
    to_run << "ALTER TABLE #{escape_table(fk[:table])} RENAME CONSTRAINT #{escape_table(fk[:from_name])} TO #{escape_table(fk[:to_name])}"
  end

  if !to_run.empty?
    to_run.unshift("\n-- update foreign keys")
  end

  return to_run
end

def calc_perms_changes schema_tables, noop
  users = ($check_perms_for.map { |user| ActiveRecord::Base::sanitize(user) }).join ","
  database = ActiveRecord::Base.connection_config[:database]
  sql = %{
    select grantee, table_name, privilege_type
    from information_schema.role_table_grants
    where table_catalog=#{ActiveRecord::Base::sanitize(database)}
      and grantee in (#{users})
      and table_schema='public';
  }
  existing_perms = Hash.new { |h, k| h[k] = Hash.new { |h, k| h[k] = Set.new } }
  build_pg_connection.exec(sql).each do |row|
    existing_perms[row['grantee']][row['table_name']].add(row['privilege_type'])
  end
  to_run = []
  schema_tables.each do |table_name, tbl|
    $check_perms_for.each do |user|
      to_grant = (tbl.perms_for_user[user] - existing_perms[user][table_name]).to_a
      to_revoke = (existing_perms[user][table_name] - tbl.perms_for_user[user]).to_a
      to_run.push("GRANT "+ to_grant.join(',') +" ON #{escape_table(table_name)} TO #{user}") unless to_grant.empty?
      to_run.push("REVOKE "+ to_revoke.join(',') +" ON #{escape_table(table_name)} FROM #{user}") unless to_revoke.empty?
    end
  end

  if !to_run.empty?
    to_run.unshift("\n-- update permissions")
  end
  
  return to_run
end


IgnoreTables = Set.new ["schema_migrations"]

def load_existing_tables()
  existing_tables = {}
  existing_indexes = []
  ActiveRecord::Base.establish_connection(get_connection_config)
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
  attr_accessor :name, :opts, :id, :columns, :perms_for_user
  
  def initialize()
    @columns = []
  end
  
  def grant *args, to: nil
    to = $db_username if to.nil?
    $check_perms_for.add(to)
    args.each do |arg|
      @perms_for_user[to] |= check_perm(arg)
    end
  end
  
  def revoke *args, from: nil
    from = $db_username if from.nil?
    $check_perms_for.add(from)
    args.each do |arg|
      @perms_for_user[from] -= check_perm(arg)
    end
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
      fk = c.opts.delete(:fk)
      if fk.present?
        if fk.respond_to?('each')
          add_foreign_key self.name, fk[0], column: c.name, primary_key: fk[1]
        else
          add_foreign_key self.name, fk, column: c.name
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
$check_perms_for = Set.new

def create_table(name, opts={})
  tbl = Table.new
  tbl.name = name
  tbl.opts = opts
  tbl.perms_for_user = Hash.new { |h, k| h[k] = Set.new }
  $default_perms_for.each do |k,v|
    tbl.perms_for_user[k] += v
  end
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

$foreign_keys = []

def add_foreign_key(from_table, to_table, opts={})
  opts = HashWithIndifferentAccess.new opts
  opts[:from_table] = from_table.to_s
  opts[:to_table] = to_table.to_s
  opts[:column] = to_table.to_s.singularize + "_id" unless opts[:column].present?
  opts[:primary_key] = "id" unless opts[:primary_key].present?
  opts[:name] = "fk #{from_table.to_s.parameterize}.#{opts[:column].to_s.parameterize} to #{to_table.to_s.parameterize}.#{opts[:primary_key].to_s.parameterize}" unless opts[:name].present?
  opts[:column] = opts[:column].to_s
  opts[:primary_key] = opts[:primary_key].to_s
  opts[:name] = opts[:name].to_s
  $foreign_keys.append(opts)
end

$allowed_perms = Set.new ["INSERT", "SELECT", "UPDATE", "DELETE", "TRUNCATE", "REFERENCES", "TRIGGER"]
$default_perms_for = Hash.new { |h, k| h[k] = Set.new }

def check_perm perm
    perm = perm.to_s.upcase
    return Set.new($allowed_perms) if perm=="ALL"
    raise ArgumentError.new("permission #{perm} is not one of #{$allowed_perms.to_a}") unless $allowed_perms.include? perm
    return Set.new [perm]
end

def grant(*perms, to: nil)
  to = $db_username if to.nil?
  $check_perms_for.add(to)
  perms.each do |perm|
    $default_perms_for[to] |= check_perm(perm)
  end
end

def revoke(*perms, from: nil)
  from = $db_username if from.nil?
  $check_perms_for.add(from)
  perms.each do |perm|
    $default_perms_for[from] -= check_perm(perm)
  end
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
  k = k.to_s if k.is_a? Symbol
  return PG::Connection.quote_ident k
end

def gen_pg_adapter()
  $tmp_to_run = []
  a = ActiveRecord::ConnectionAdapters::PostgreSQLAdapter.allocate
  ActiveRecord::ConnectionAdapters::AbstractAdapter.instance_method(:initialize).bind(a).call ActiveRecord::Base.connection
  return a
end

def sql_renames(renames)
  pg_a = gen_pg_adapter()
  renames.each do |k,v|
    pg_a.rename_table(k, v)
  end
  to_run = $tmp_to_run.clone
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
    if !$check_perms_for.empty?
      $tmp_to_run << "REVOKE ALL ON #{(tables.map {|t| escape_table(t)}).join(',')} FROM #{$check_perms_for.to_a.join(',')}"
    end
  end
  return $tmp_to_run.clone
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

