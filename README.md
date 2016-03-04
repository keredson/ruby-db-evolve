
Ruby DB::Evolve
===============

Introduction
----------------

**TL;DR:** *DB::Evolve is to Ruby Migrations as React is to jQuery.*

If I'm defining some structured data (like a schema), I want to simply define it outright.  Rather than writing a bunch of diffs/deltas/migrations and letting a tool rebuild the structure I want to write the structure and have a tool build the diffs/deltas/migrations.  It's more efficient and less error prone, which makes it cheaper.  And if it's cheaper I'm more likely to do it, which means I'm less likely to work around bad schemas, which leads to better schemas overall.  *Win.*

So I wrote [such a tool](https://github.com/keredson/deseb) for Python/Django back in 2006 (for Google's Summer of Code).  I still use it today.

I'm now working in Ruby, and boy do I miss it.  So I ported it.

Prereqs:

1.  A schema DSL (hey look, `schema.rb`)
2. DB schema extraction (already built into the connectoin object)

What it should do:

1. Diff `schema.rb` and the live database.
2. Generate CREATE/ALTER TABLE/COLUMN statements to bring to database in line with `schema.rb`.

How it should work in practice:

1. I want a new column.
2. I add a new line to `schema.db`.
3. I run `rake db:evolve`.
4. An `ALTER TABLE ADD COLUMN` statement is generated, I preview it, and say `yes` to run it.

Install
---------

1. Add `gem 'db-evolve'` to your `Gemfile`.
2. `$ bundle install`

Quick Start
---------------------

Let's say your `schema.rb` looks like this:

```ruby
ActiveRecord::Schema.define(:version => 20150402195918) do
  create_table "comments" do |t|
    t.integer  "post_id",       :null => false
    t.integer  "author_id"
    t.datetime "created_at",    :null => false
    t.datetime "updated_at",    :null => false
    t.text     "text"
  end
end
```

To enable schema evolution change this:

```ruby
ActiveRecord::Schema.define(:version => 20150402195918) do
```

to this:

```ruby
DB::Evolve::Schema.define do
```

And then run this:

```
$ rake db:evolve
```

It'll do nothing (assuming your database is up to date).  YAY!

Now tweak a column:

```ruby
  create_table "user_comments", :aka => "comments" do |t|
```

Oh look, we renamed a column.  Let's run again:

```sql
$ rake db:evolve

BEGIN TRANSACTION;

-- rename tables
ALTER TABLE "comments" RENAME TO "user_comments";

COMMIT;
```

Holy bejeezus!

Let's try another:

```ruby
    t.text     "body", :aka => "text"
```

Run again...

```sql
$ rake db:evolve

BEGIN TRANSACTION;

-- column changes for user_comments
ALTER TABLE "user_comments" RENAME COLUMN "text" TO "body";

COMMIT;
```

You get the idea.  Stop writing your own diffs to apply to your schema.  Just write your schema!


Database Permission Management
------------------------------
To manage table level permissions db:evolve has several directives available.  To grant everything, use `grant`:

```ruby
DB::Evolve::Schema.define do
  grant :all
  create_table "whatever" do |t|
    [...]
```

Acceptable options are `:insert`, `:select`, `:update`, `:delete`, `:truncate`, `:references`, `:trigger` and `:all`.

To grant everything except `:references` and `:trigger`:
```ruby
DB::Evolve::Schema.define do
  grant :all
  revoke :references, :trigger
  create_table "whatever" do |t|
    [...]
```

Order is important, including between `create_table` statements.  Grants/revokes only effect the tables defined after them.

If you want to grant or revoke permissions on a specific table:

```ruby
  create_table "whatever" do |t|
    t.string   "some_sort_of_log_info"
    t.revoke :update, :delete
  end
```

Grant and revoke by default apply to the current db user (as defined by your env in `database.yml`), but you can mange other users as well:

```ruby
  create_table "whatever" do |t|
    t.string   "some_sort_of_log_info"
    t.revoke :update, :delete, from: "normal_user"
    t.grant :update, :delete, to: "admin_user"
  end
```

DB::Evolve will only update permissions for users specifically mentioned (via `from` or `to`, or in `database.yml` for the given environment), not every user in the database.

Schema Change Permissions
-------------------------
Normally, in production, you don't want your web server's database account to have permissions to modify your schema.  To have db:evolve run the schema changes as a different user than the user for your environment, create a second db env with the same name, but with `_dbevolve` appended.  For example, if my `datebase.yml` looks like:

```
production:
  adapter: postgresql
  database: mysite_prod
  host: localhost
  username: www
  password: passw0rd
```

Adding this would work:

```
production_dbevolve:
  adapter: postgresql
  database: mysite_prod
  host: localhost
  username: postgres
  password: 5uper5ecret
```

Or more simply this:
```
production_dbevolve:
  adapter: postgresql
  database: mysite_prod
  # not specifying the host, username and password makes postgres use local auth,
  # assuming your local user has permissions to modify the schema.
```

Status
--------

* PostgreSQL only ATM.
* Feature complete (ADD/DROP/RENAME tables, columns and indexes, ALTER types, limits, nullable, precision, scale).
* GRAS (Generally Recognized as Safe).  It prompts yes/no before running any SQL.  And switching back to migrations is just as easy as switching to DB::Evolve.


FAQ
------

*Q: But the file `schema.rb` is autogenerated and shouldn't be manually altered?!?*

A: Now it will NOT be auto-genned, and you will manipulate it like the authoritative data-source that it claims to be.  It's a good schema DSL, and everyone already has one, so using it makes sense.



Derek's S#!tty Version Control System
--------------------------------------------------

*AKA the "why did you do this?" section.*

Allow me to introduce DSVCS (Derek's S#!tty Version Control System).  It works a little different from how you'd expect.
Rather than write your code in a file and let a tool figure out the history, DSVCS gives you full control of the history
tracking progress.  It's a revolutionary new coding process.  Watch how easy it is!

To start a new file, simply create a new directory `my_file.rb`.  The directory name, by convention, becomes your final file name.

In that directory, create a new file `1.diff`:

<pre>
0a1,2
> class MyClass
> end
</pre>

If you recognize this as an industry standard diff file, congrats!  YOU'RE GETTING IT!

Now when you want to use your file, just build it first.  DSVCS has a built in tool to re-generate your final file from whatever series of diffs you've defined.  Just run:

```
$ dsvcs-generate my_file.rb > build/my_file.rb
```

This will open the directory `my_file.rb`, run each diff in sequence and write the results to `build/my_file.rb`.  It couldn't be easier!

Now let's make it do something by adding `2.diff`:

<pre>
1a2,4
>   def hi()
>     puts "Helo World!"
>   end
</pre>

Now run:

```
$ dsvcs-generate my_file.rb > build/my_file.rb
```

Oh oh, I think I made a typo.  No matter, just write `3.diff`:

<pre>
3c3
<     puts "Helo World!"
---
>     puts "Hello World!"
</pre>

And you're done!

Can't you just feel the power of DSVCS?  No, well then you clearly **Just Don't Get It<sup>TM</sup>**!

-- Derek

I'm a relative novice in the Ruby world.  But this spoofed VCS should give you a fair approximation how crazy the [official active record migratoin documentation](http://guides.rubyonrails.org/active_record_migrations.html) reads to me.



