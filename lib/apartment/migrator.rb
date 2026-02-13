require 'apartment/tenant'

module Apartment
  module Migrator

    extend self

    def migrate(database)
      Tenant.switch(database) do
        version = ENV["VERSION"] ? ENV["VERSION"].to_i : nil
        migration_scope_block = ->(migration) { ENV["SCOPE"].blank? || (ENV["SCOPE"] == migration.scope) }

        migration_context.migrate(version, &migration_scope_block)
      end
    end

    def run(direction, database, version)
      Tenant.switch(database) do
        migration_context.run(direction, version)
      end
    end

    def rollback(database, step = 1)
      Tenant.switch(database) do
        migration_context.rollback(step)
      end
    end

    private

    def migration_context
      ActiveRecord::Base.connection.migration_context
    end
  end
end
