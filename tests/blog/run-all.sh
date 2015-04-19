#!/bin/bash

mkdir -p db

dropdb db_evolve_test

set -e

createdb db_evolve_test

for i in $( ls schemas/*.rb -1v ); do
    echo "----------------------------------------------"
    echo " Running: $i"
    echo "----------------------------------------------"
    cp $i db/schema.rb
    rake db:evolve[yes,nowait]
    NOOP=$(rake db:evolve[noop])
    if [ -n "$NOOP" ]; then
      echo "Failed NOOP: $i"
      echo $NOOP
      exit 1
    fi
    set +e
    pg_dump db_evolve_test --schema-only --no-owner --no-acl | \
        grep -v "^--" | grep -v "^$" | grep -v "^SET " | \
        grep -v "^CREATE EXTENSION" | grep -v "^COMMENT ON EXTENSION" \
        > /tmp/db_evolve_test_schema.sql
    SQL_FILE="${i%.*}.sql"
    if [ ! -f "$SQL_FILE" ]; then
      echo "ERROR - Missing schema comparison: $SQL_FILE"
      exit 1
    fi 
    DIFF=$(diff /tmp/db_evolve_test_schema.sql "$SQL_FILE")
    set -e
    if [ -n "$DIFF" ]; then
      echo "Failed DIFF: $i"
      echo $DIFF
      exit 1
    fi
done

echo "----------------------------------------------"
echo "Passed all tests!"
echo "----------------------------------------------"


