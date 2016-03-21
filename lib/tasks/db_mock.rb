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
      def clear
        return nil
      end
    end
    class PostgreSQLAdapter
      def execute(sql, name = nil)
        $tmp_to_run.append sql
        return FakeResult.new
      end
      def async_exec(sql, params_result_format)
        $tmp_to_run.append sql
        return FakeResult.new
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

