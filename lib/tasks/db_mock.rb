require 'mysql'
require 'pg'

module ActiveRecord
  module ConnectionAdapters
    class PostgreSQLAdapter
      def execute(sql, name = nil)
        $tmp_to_run.append sql
      end
      def table_exists?(name)
        false
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
    class MysqlAdapter
      alias_method :real_execute, :execute
      def initialize()
        @visitor = nil
        @quoted_column_names, @quoted_table_names = {}, {}
        config = ActiveRecord::Base.connection_config
        @conn = Mysql.new(config[:host], config[:username], config[:password], config[:database])
      end
      def execute(sql, name = nil)
        if sql.start_with?('SHOW FULL FIELDS')
          @connection = @conn
          return @conn.query(sql)
        end
        $tmp_to_run.append sql
      end
      def table_exists?(name)
        false
      end
      def clear_cache!
      end
      def escape(s)
        return PG::Connection.quote_ident s
      end
      def each_hash(result) # :nodoc:
        if block_given?
          result.each_hash do |row|
            row.symbolize_keys!
            yield row
          end
        else
          to_enum(:each_hash, result)
        end
      end
    end
  end
end

