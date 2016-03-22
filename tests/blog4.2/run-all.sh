#!/bin/bash

mkdir -p db

dropdb db_evolve_test
echo "CREATE USER db_evolve_test WITH PASSWORD 'password';" | psql template1
echo "CREATE USER db_evolve_test2 WITH PASSWORD 'password';" | psql template1

set -e

createdb -O db_evolve_test db_evolve_test

for i in $( ls schemas/*.rb -1v ); do
    echo "----------------------------------------------"
    echo " Running: $i"
    echo "----------------------------------------------"
    cp $i db/schema.rb
    bundle exec rake db:evolve[yes,nowait]
    NOOP=$(bundle exec rake db:evolve[noop])
    if [ -n "$NOOP" ]; then
      echo "Failed NOOP: $i"
      echo $NOOP
      exit 1
    fi
    set +e
    pg_dump db_evolve_test --schema-only --no-owner | \
        grep -v "^--" | grep -v "^$" | grep -v "^SET " | \
        grep -v "^CREATE EXTENSION" | grep -v "^COMMENT ON EXTENSION" | \
        grep -v "^REVOKE ALL ON SCHEMA" | grep -v "^GRANT ALL ON SCHEMA" | \
        grep -v "^REVOKE ALL ON TABLE .* FROM `whoami`;" | grep -v "^GRANT ALL ON TABLE .* TO `whoami`;" \
        > /tmp/db_evolve_test_schema.sql
    SQL_FILE="${i%.*}.sql"
    if [ ! -f "$SQL_FILE" ]; then
      echo "ERROR - Missing schema comparison: $SQL_FILE (to compare to /tmp/db_evolve_test_schema.sql)"
      exit 1
    fi 
    DIFF=$(diff /tmp/db_evolve_test_schema.sql "$SQL_FILE")
    set -e
    if [ -n "$DIFF" ]; then
      echo "Failed DIFF: /tmp/db_evolve_test_schema.sql != $SQL_FILE for $i"
      echo "$DIFF"
      exit 1
    fi
done

echo "----------------------------------------------"
echo "Passed all tests!"
echo "----------------------------------------------"


