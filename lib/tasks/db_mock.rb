require 'pg'

module ActiveRecord
  module ConnectionAdapters
    class FakeResult
      def fields
        return []
      end
      def values
        return []
      end
      def first
        return {}
      end
      def clear
        return nil
      end
    end
    class PostgreSQLAdapter
      def execute(sql, name = nil)
        $tmp_to_run.append sql unless skip? sql
        return FakeResult.new
      end
      def async_exec(sql, params_result_format)
        $tmp_to_run.append sql unless skip? sql
        return FakeResult.new
      end
      def skip? sql
        return true if sql.end_with?("'::regtype::oid") and sql.start_with?("SELECT '")
        return false 
      end
      def table_exists?(name)
        false
      end
      def columns(table_name)
        return @@existing_tables[table_name]
      end
      def self.existing_tables= existing_tables
        @@existing_tables = existing_tables
      end
      def self.server_version= server_version
        @@server_version = server_version 
      end
      def server_version
        return @@server_version
      end
      def initialize_type_map m
        # do nothing
      end
      def clear_cache!
      end
      def quote_string s
        # hack to prevent double-quoting when setting default
        return s
      end
      def escape(s)
        return PG::Connection.quote_ident s
      end
    end
  end
end

