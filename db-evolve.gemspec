Gem::Specification.new do |s|
  s.name        = 'db-evolve'
  s.version     = '0.1.4'
  s.date        = '2015-08-06'
  s.summary     = "Schema Evolution for Ruby"
  s.description = "A diff/patch between your schema.rb and what's in your database."
  s.authors     = ["Derek Anderson"]
  s.email       = 'public@kered.org'
  s.files       = ["lib/db-evolve.rb", "lib/tasks/db.rb", "lib/tasks/db_mock.rb", "lib/tasks/sql_color.rb"]
  s.homepage    = 'https://github.com/keredson/ruby-db-evolve'
  s.license       = 'GPLv2'
end

