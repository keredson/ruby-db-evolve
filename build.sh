gem build db-evolve.gemspec | grep "File:" | cut -d' ' -f4 | xargs sudo gem install
