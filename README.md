
Rails DB Evolve
===============

Introduction
----------------

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


Introduction (Take 2)
---------------------------

I'm a relative novice in the Ruby world.  But this spoofed VCS should give you a fair approximation how crazy the [official active record migratoin documentation](http://guides.rubyonrails.org/active_record_migrations.html) reads to me.  Most notably crap like this:

```
$ bin/rails generate migration AddPartNumberToProducts part_number:string
```

I mean, WTF?  I'd rather write SQL!

And then I found `db/schema.db` with its wonderful header:

<pre>
# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# Note that this schema.rb definition is the authoritative source for your
# database schema. If you need to create the application database on another
# system, you should be using db:schema:load, not running all the migrations
# from scratch. The latter is a flawed and unsustainable approach (the more migrations
# you'll amass, the slower it'll run and the greater likelihood for issues).
#
# It's strongly recommended to check this file into your version control system.
</pre>

Some choice excerpts:

`Note that this schema.rb definition is the authoritative source...`

But the code doesn't use it at run-time?  Only when you call `db:schema:load` once every 2 years when you buy a new laptop?  *(sigh)*

`The latter is a flawed and unsustainable approach...`

OK, so they know it's broken... *(double sigh)*

`This file is auto-generated from the current state of the database.` ... `It's strongly recommended to check this file into your version control system.`

[ARRRGGGGGHHHHHH.....](http://lmgtfy.com/?q=code+generation+is+evil)

On the plus side, this isn't bad for a schema DSL:

<pre>
ActiveRecord::Schema.define(:version => 20150402195918) do
  create_table "comments" do |t|
    t.integer  "post_id",       :null => false
    t.integer  "author_id"
    t.datetime "created_at",    :null => false
    t.datetime "updated_at",    :null => false
    t.text     "text"
  end
end
</pre>

And it appears damn near everyone has one laying around.  Why don't we honor the header (make it the authoritative source), stop auto-generating it, and just maintain it directly?  And then write a diff tool that will show you how your `schema.rb` differs from your database's schema, and generate the SQL to bring your database up to speed?

**NOW YOU GET IT!<sup>TM</sup>**

Quick Start
---------------------

Change this:

<pre>
ActiveRecord::Schema.define(:version => 20150402195918) do
</pre>

to this:

<pre>
DB::Schema.define do
</pre>

And then run this:

```
$ rake db:evolve
```

It'll do nothing (assuming your database is up to date).  YAY!

Now tweak a column:

<pre>
  create_table "user_comments", :aka => "comments" do |t|
</pre>

Oh look, we renamed a column.  Let's run again:

<pre>
$ rake db:evolve

BEGIN TRANSACTION;

-- rename tables
ALTER TABLE "comments" RENAME TO "user_comments";

COMMIT;
</pre>

Holy bejeezus!

Let's try another:

<pre>
    t.text     "body", :aka => "text"
</pre>

Run again...

<pre>
$ rake db:evolve

BEGIN TRANSACTION;

-- column changes for user_comments
ALTER TABLE "user_comments" RENAME COLUMN "text" TO "body";

COMMIT;
</pre>

You get the idea.  Stop writing your own diffs to apply to your schema.  Just write your schema, and use a f#*king `diff` tool!


Status
--------
Version 0.0.1.  Very experimental.  PostgreSQL only.  Use at your own risk!



