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
    end
  end
end

