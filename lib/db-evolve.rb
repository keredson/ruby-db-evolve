require 'rails'
class RubyDBEvolve
  class Railtie < Rails::Railtie
    rake_tasks do
      require_relative 'tasks/db'
    end
  end
end

