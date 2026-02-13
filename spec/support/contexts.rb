#   Some shared contexts for specs

shared_context "with default schema", :default_schema => true do
  let(:default_schema){ Apartment::Test.next_db }

  before do
    Apartment::Test.create_schema(default_schema)
    Apartment.default_schema = default_schema
  end

  after do
    # resetting default_schema so we can drop and any further resets won't try to access droppped schema
    Apartment.default_schema = nil
    Apartment::Test.drop_schema(default_schema)
  end
end

# Some default setup for elevator specs
shared_context "elevators", elevator: true do
  let(:company1)  { instance_double(Company, database: db1) }
  let(:company2)  { instance_double(Company, database: db2) }

  let(:api)       { Apartment::Tenant }

  before do
    Apartment.reset # reset all config
    Apartment.seed_after_create = false
    Apartment.use_schemas = true
    api.reload!(config)
    api.create(db1)
    api.create(db2)
  end

  after do
    api.drop(db1)
    api.drop(db2)
  end
end

shared_context "persistent_schemas", :persistent_schemas => true do
  let(:persistent_schemas){ ['hstore', 'postgis'] }

  before do
    persistent_schemas.map{|schema| subject.create(schema) }
    Apartment.persistent_schemas = persistent_schemas
  end

  after do
    Apartment.persistent_schemas = []
    persistent_schemas.map{|schema| subject.drop(schema) }
  end
end