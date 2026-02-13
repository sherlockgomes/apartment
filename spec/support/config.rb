require 'yaml'

module Apartment
  module Test

    def self.config
      @config ||= YAML.safe_load(
        ERB.new(IO.read('spec/config/database.yml')).result,
        permitted_classes: [Symbol],
        aliases: true
      )
    end
  end
end