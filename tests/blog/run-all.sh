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
    rake db:evolve[yes]
    NOOP=$(rake db:evolve[noop])
    if [ -n "$NOOP" ]; then
      echo "Failed NOOP: $i"
      echo $NOOP
      exit 1
    fi
    pg_dump db_evolve_test --schema-only --no-owner --no-acl | \
        grep -v "^--" | grep -v "^$" | grep -v "^SET " | \
        grep -v "^CREATE EXTENSION" | grep -v "^COMMENT ON EXTENSION" \
        > /tmp/db_evolve_test_schema.sql
    set +e
    DIFF=$(diff /tmp/db_evolve_test_schema.sql ${i%.*}.sql)
    set -e
    if [ -n "$DIFF" ]; then
      echo "Failed DIFF: $i"
      echo $DIFF
      exit 1
    fi
done

echo "Passed all tests!"


