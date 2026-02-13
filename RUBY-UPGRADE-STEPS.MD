# Passos de Upgrade — Apartment para Ruby 3.3+ / Rails 7+ (8+)

Este documento lista **todos os passos necessários**, na ordem recomendada de execução, para atualizar a gem Apartment (v2.2.1, parada em Rails 6.0/Ruby 2.x) para funcionar com **Ruby 3.3+** e **Rails 7+/8+** com **PostgreSQL 15+**.

Cada passo inclui: o que mudar, por que mudar, quais arquivos são afetados, e o código antes/depois.

---

## Fase 1 — Gemspec e Dependências

### Passo 1.1 — Atualizar restrições do gemspec

**Arquivo:** `apartment.gemspec`

**Por quê:** O gemspec restringe `activerecord < 6.1`, `rake ~> 0.9`, `bundler < 2.0`, `sqlite3 ~> 1.3.6`, etc. Essas restrições impedem a instalação com Rails 7+/8+.

**Antes:**
```ruby
s.add_dependency 'activerecord',    '>= 3.1.2', '< 6.1'
s.add_dependency 'rack',            '>= 1.3.6'
s.add_dependency 'public_suffix',   '>= 2'
s.add_dependency 'parallel',        '>= 0.7.1'

s.add_development_dependency 'appraisal'
s.add_development_dependency 'rake',         '~> 0.9'
s.add_development_dependency 'rspec',        '~> 3.4'
s.add_development_dependency 'rspec-rails',  '~> 3.4'
s.add_development_dependency 'capybara',     '~> 2.0'
s.add_development_dependency 'bundler',      '>= 1.3', '< 2.0'
# ...
s.add_development_dependency 'sqlite3', '~> 1.3.6'
```

**Depois:**
```ruby
s.add_dependency 'activerecord',    '>= 7.0'
s.add_dependency 'rack',            '>= 2.0'
s.add_dependency 'public_suffix',   '>= 5'
s.add_dependency 'parallel',        '>= 1.20'

s.add_development_dependency 'appraisal'
s.add_development_dependency 'rake',         '>= 13.0'
s.add_development_dependency 'rspec',        '~> 3.12'
s.add_development_dependency 'rspec-rails',  '~> 6.0'
s.add_development_dependency 'capybara',     '~> 3.0'
s.add_development_dependency 'bundler',      '>= 2.0'
# ...
s.add_development_dependency 'sqlite3', '>= 1.7'
```

**Nota:** Se o foco é apenas PostgreSQL 15+, pode-se simplificar e remover dependências sqlite3 e mysql2 do gemspec de desenvolvimento.

### Passo 1.2 — Atualizar Gemfile

**Arquivo:** `Gemfile`

**Antes:**
```ruby
gem 'rails', '>= 3.1.2'
```

**Depois:**
```ruby
gem 'rails', '>= 7.0'
```

### Passo 1.3 — Atualizar Appraisals

**Arquivo:** `Appraisals`

**Por quê:** Remover appraisals de Rails 4.x/5.x/6.0 e manter apenas 7.x/8.x.

**Depois:**
```ruby
appraise "rails-7-1" do
  gem "rails", "~> 7.1.0"
end

appraise "rails-7-2" do
  gem "rails", "~> 7.2.0"
end

appraise "rails-8-0" do
  gem "rails", "~> 8.0.0"
end
```

### Passo 1.4 — Atualizar versão da gem

**Arquivo:** `lib/apartment/version.rb`

**Antes:**
```ruby
VERSION = "2.2.1"
```

**Depois:**
```ruby
VERSION = "3.0.0"
```

---

## Fase 2 — Ruby 3.x: Correções de Linguagem

### Passo 2.1 — Substituir `File.exists?` por `File.exist?`

**Por quê:** `File.exists?` foi depreciado no Ruby 2.7 e **removido no Ruby 3.2**. Causa `NoMethodError` imediato.

**Arquivos afetados:**

1. `lib/apartment/adapters/abstract_adapter.rb` (linha 212)
2. `lib/apartment/adapters/sqlite3_adapter.rb` (linhas 20, 33, 40)
3. `Rakefile` (linhas 43, 44)
4. `spec/adapters/sqlite3_adapter_spec.rb` (linhas 43, 58, 76)

**Ação:** Substituir toda ocorrência de `File.exists?` por `File.exist?` nos arquivos acima.

### Passo 2.2 — Corrigir `YAML.load` sem `permitted_classes`

**Por quê:** A partir do Ruby 3.1, `YAML.load` usa `Psych 4` por padrão, que requer `permitted_classes` ou uso de `YAML.safe_load`. Sem isso, classes como `Symbol` e `Date` não são deserializadas.

**Arquivo:** `spec/support/config.rb`

**Antes:**
```ruby
@config ||= YAML.load(ERB.new(IO.read('spec/config/database.yml')).result)
```

**Depois:**
```ruby
@config ||= YAML.safe_load(
  ERB.new(IO.read('spec/config/database.yml')).result,
  permitted_classes: [Symbol],
  aliases: true
)
```

---

## Fase 3 — Rails 7+: APIs Depreciadas/Removidas do ActiveRecord

### Passo 3.1 — Substituir `connection_config` por `connection_db_config`

**Por quê:** `ActiveRecord::Base.connection_config` foi depreciado no Rails 6.1 e **removido no Rails 7.1**. Deve ser substituído por `connection_db_config.configuration_hash`.

**Diferença importante:** `connection_config` retornava um hash com chaves symbol. `connection_db_config.configuration_hash` retorna um hash **frozen** com chaves symbol. Para manter compatibilidade, usar `.dup` quando necessário.

#### Arquivo: `lib/apartment.rb`

**Antes (linha 19):**
```ruby
def_delegators :connection_class, :connection, :connection_config, :establish_connection
```

**Depois:**
```ruby
def_delegators :connection_class, :connection, :establish_connection

def connection_config
  connection_db_config.configuration_hash
end
```

**Nota:** `connection_config` é usado internamente em vários lugares. Manter como wrapper garante compatibilidade interna.

#### Arquivo: `lib/apartment/tenant.rb`

**Antes (linha 63):**
```ruby
def config
  @config ||= Apartment.connection_config
end
```

**Depois:**
```ruby
def config
  @config ||= Apartment.connection_config.dup
end
```

#### Arquivo: `lib/apartment/adapters/postgresql_adapter.rb`

**Antes (linha 232):**
```ruby
def dbname
  Apartment.connection_config[:database]
end
```

**Depois:**
```ruby
def dbname
  Apartment.connection_config[:database]
end
```

Este não precisa mudar porque usará o wrapper definido no passo acima.

#### Arquivo: `spec/unit/config_spec.rb`

**Antes (linha 12):**
```ruby
hash[tenant] = Apartment.connection_config
```

**Depois:**
```ruby
hash[tenant] = Apartment.connection_config
```

Não precisa mudar — o wrapper cuida disso.

### Passo 3.2 — Substituir `establish_connection` com hash por `DatabaseConfig`

**Por quê:** No Rails 7+, `establish_connection` aceita um hash mas internamente cria um `DatabaseConfig`. O hash passado a `establish_connection` deve ter chaves symbol (não string). No Rails 7.1+, quando se passa um config hash, internamente é criado um `HashConfig`.

**Arquivos afetados:**
- `lib/apartment/adapters/abstract_adapter.rb` (linhas 112, 145, 176, 241)

**Ação:** Garantir que todo hash passado a `establish_connection` tenha chaves symbol:

**Antes (linha 112):**
```ruby
def reset
  Apartment.establish_connection @config
end
```

**Depois:**
```ruby
def reset
  Apartment.establish_connection @config.symbolize_keys
end
```

**Antes (linha 145):**
```ruby
def process_excluded_model(excluded_model)
  excluded_model.constantize.establish_connection @config
end
```

**Depois:**
```ruby
def process_excluded_model(excluded_model)
  excluded_model.constantize.establish_connection @config.symbolize_keys
end
```

**Antes (linha 176):**
```ruby
Apartment.establish_connection multi_tenantify(tenant)
```

**Depois:**
```ruby
Apartment.establish_connection multi_tenantify(tenant).symbolize_keys
```

**Antes (linha 241):**
```ruby
SeparateDbConnectionHandler.establish_connection(multi_tenantify(tenant, false))
```

**Depois:**
```ruby
SeparateDbConnectionHandler.establish_connection(multi_tenantify(tenant, false).symbolize_keys)
```

### Passo 3.3 — Modernizar `Apartment::Migrator`

**Por quê:** No Rails 7+, `ActiveRecord::Migrator.migrate`, `.run` e `.rollback` com paths foram removidos. Apenas `ActiveRecord::MigrationContext` é suportado. Além disso, no Rails 7.1+, `MigrationContext.new` não aceita mais paths como argumento — usa `ActiveRecord::Base.connection.migration_context` diretamente.

**Arquivo:** `lib/apartment/migrator.rb`

**Antes:**
```ruby
require 'apartment/tenant'

module Apartment
  module Migrator
    extend self

    def migrate(database)
      Tenant.switch(database) do
        version = ENV["VERSION"] ? ENV["VERSION"].to_i : nil
        migration_scope_block = -> (migration) { ENV["SCOPE"].blank? || (ENV["SCOPE"] == migration.scope) }

        if activerecord_below_5_2?
          ActiveRecord::Migrator.migrate(ActiveRecord::Migrator.migrations_paths, version, &migration_scope_block)
        else
          ActiveRecord::Base.connection.migration_context.migrate(version, &migration_scope_block)
        end
      end
    end

    def run(direction, database, version)
      Tenant.switch(database) do
        if activerecord_below_5_2?
          ActiveRecord::Migrator.run(direction, ActiveRecord::Migrator.migrations_paths, version)
        else
          ActiveRecord::Base.connection.migration_context.run(direction, version)
        end
      end
    end

    def rollback(database, step = 1)
      Tenant.switch(database) do
        if activerecord_below_5_2?
          ActiveRecord::Migrator.rollback(ActiveRecord::Migrator.migrations_paths, step)
        else
          ActiveRecord::Base.connection.migration_context.rollback(step)
        end
      end
    end

    private

    def activerecord_below_5_2?
      ActiveRecord.version.release < Gem::Version.new('5.2.0')
    end
  end
end
```

**Depois:**
```ruby
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
```

### Passo 3.4 — Remover workaround de PostgreSQL < 9.3

**Por quê:** PostgreSQL 15+ é o alvo. O workaround para `postgresql_version < 90300` (PostgreSQL < 9.3) e o uso de `send(:postgresql_version)` (que é público desde Rails 5.0) são desnecessários.

**Arquivo:** `lib/apartment/adapters/postgresql_adapter.rb`

**Antes (linhas 64-80):**
```ruby
def connect_to_new(tenant = nil)
  return reset if tenant.nil?
  raise ActiveRecord::StatementInvalid.new("Could not find schema #{tenant}") unless Apartment.connection.schema_exists?(tenant.to_s)

  @current = tenant.to_s
  Apartment.connection.schema_search_path = full_search_path

  # When the PostgreSQL version is < 9.3,
  # there is a issue for prepared statement with changing search_path.
  # https://www.postgresql.org/docs/9.3/static/sql-prepare.html
  if postgresql_version < 90300
    Apartment.connection.clear_cache!
  end

rescue *rescuable_exceptions
  raise TenantNotFound, "One of the following schema(s) is invalid: \"#{tenant}\" #{full_search_path}"
end
```

**Depois:**
```ruby
def connect_to_new(tenant = nil)
  return reset if tenant.nil?
  raise ActiveRecord::StatementInvalid.new("Could not find schema #{tenant}") unless Apartment.connection.schema_exists?(tenant.to_s)

  @current = tenant.to_s
  Apartment.connection.schema_search_path = full_search_path

rescue *rescuable_exceptions
  raise TenantNotFound, "One of the following schema(s) is invalid: \"#{tenant}\" #{full_search_path}"
end
```

**Também remover** o método privado `postgresql_version` (linhas 98-101):
```ruby
# REMOVER:
def postgresql_version
  Apartment.connection.send(:postgresql_version)
end
```

### Passo 3.5 — Atualizar Railtie para Rails 7+

**Por quê:** Vários pontos do Railtie são incompatíveis:
- `ActiveRecord::Migrator.migrations_paths =` — no Rails 7+ o assignment direto não funciona da mesma forma.
- `config.to_prepare` — funciona, mas o bloco interno precisa de ajuste.
- `ActiveRecord::NoDatabaseError` — a rescue está ok.

**Arquivo:** `lib/apartment/railtie.rb`

**Antes (linha 22):**
```ruby
config.before_initialize do
  Apartment.configure do |config|
    config.excluded_models = []
    config.use_schemas = true
    config.tenant_names = []
    config.seed_after_create = false
    config.prepend_environment = false
    config.append_environment = false
  end

  ActiveRecord::Migrator.migrations_paths = Rails.application.paths['db/migrate'].to_a
end
```

**Depois:**
```ruby
config.before_initialize do
  Apartment.configure do |config|
    config.excluded_models = []
    config.use_schemas = true
    config.tenant_names = []
    config.seed_after_create = false
    config.prepend_environment = false
    config.append_environment = false
  end
end
```

**Nota:** Remover a linha `ActiveRecord::Migrator.migrations_paths =`. No Rails 7+, os migration paths são gerenciados via `Rails.application.paths['db/migrate']` automaticamente.

### Passo 3.6 — Corrigir `ActionDispatch::Callbacks` no console

**Por quê:** `ActionDispatch::Callbacks.new(Proc.new {}).call({})` não funciona no Rails 7+. A forma de triggerar `to_prepare` mudou.

**Arquivo:** `lib/apartment/console.rb`

**Antes:**
```ruby
def reload!(print=true)
  puts "Reloading..." if print
  ActionDispatch::Callbacks.new(Proc.new {}).call({})
  Apartment::Tenant.init
  true
end
```

**Depois:**
```ruby
def reload!(print=true)
  puts "Reloading..." if print
  ActionDispatch::Reloader.new(Proc.new {}).call({})
  Apartment::Tenant.init
  true
end
```

**Alternativa mais segura (Rails 7.1+):**
```ruby
def reload!(print=true)
  puts "Reloading..." if print
  if Rails.application.reloader.respond_to?(:reload!)
    Rails.application.reloader.reload!
  end
  Apartment::Tenant.init
  true
end
```

### Passo 3.7 — Corrigir `ActiveRecord::Schema.define` nos schemas de teste

**Por quê:** No Rails 7.1+, `ActiveRecord::Schema.define` foi substituído por `ActiveRecord::Schema[7.1].define`. No Rails 7.0 ambos funcionam, mas a partir do 7.2 a versão sem número gera deprecation warning.

**Arquivos afetados:**
- `spec/schemas/v1.rb`
- `spec/schemas/v2.rb`
- `spec/schemas/v3.rb`
- `spec/dummy/db/schema.rb`

**Antes:**
```ruby
ActiveRecord::Schema.define(:version => 20111202022214) do
```

**Depois:**
```ruby
ActiveRecord::Schema[7.1].define(version: 20111202022214) do
```

**Nota:** A versão do schema (ex: `7.1`) deve corresponder à versão mínima do Rails suportada. Usar `7.1` como piso.

### Passo 3.8 — Corrigir `show_exceptions` no dummy app

**Por quê:** No Rails 7.1+, `config.action_dispatch.show_exceptions` mudou de boolean para symbol (`:all`, `:rescuable`, `:none`).

**Arquivos afetados:**
- `spec/dummy/config/environments/test.rb`
- `spec/dummy_engine/test/dummy/config/environments/test.rb`

**Antes:**
```ruby
config.action_dispatch.show_exceptions = false
```

**Depois:**
```ruby
config.action_dispatch.show_exceptions = :none
```

### Passo 3.9 — Substituir `secret_token` por `secret_key_base`

**Por quê:** `secret_token` foi removido no Rails 5.2+. O dummy app precisa usar `secret_key_base`.

**Arquivo:** `spec/dummy/config/initializers/secret_token.rb`

**Antes:**
```ruby
Dummy::Application.config.secret_token = '7d33999a...'
```

**Depois (renomear arquivo para `secret_key_base.rb`):**
```ruby
Dummy::Application.config.secret_key_base = '7d33999a86884f74c897c98ecca4277090b69e9f23df8d74bcadd57435320a7a16de67966f9b69d62e7d5ec553bd2febbe64c721e05bc1bc1e82c7a7d2395201'
```

### Passo 3.10 — Corrigir `database_configuration =` no setup de testes

**Por quê:** No Rails 7+, `Rails.configuration.database_configuration =` com hash vazio pode causar problemas. No Rails 7.2+, `database_configuration` retorna objetos `DatabaseConfig` em vez de hash.

**Arquivo:** `spec/support/setup.rb`

**Antes (linha 29):**
```ruby
Rails.configuration.database_configuration = {}
```

**Depois:**
```ruby
# No Rails 7+, o reset da configuração é gerenciado internamente
# Apenas limpar as conexões é suficiente
```

Ou seja, **remover** essa linha. O `clear_all_connections!` na linha seguinte já cuida da limpeza.

### Passo 3.11 — Corrigir `connection.tables` depreciado

**Por quê:** `connection.tables` foi depreciado no Rails 5.1+ em favor de `connection.data_sources` (que inclui views) ou `connection.tables` (que no Rails 7+ retorna apenas tabelas, sem schema prefix). Na prática funciona, mas o comportamento pode diferir.

**Arquivos afetados:**
- `spec/examples/generic_adapter_examples.rb` (linha 42)
- `spec/examples/schema_adapter_examples.rb` (linha 62)

**Ação:** Manter `connection.tables` — no Rails 7+ funciona corretamente. Apenas verificar se os specs passam.

### Passo 3.12 — Corrigir `remove_connection` sem argumento

**Por quê:** No Rails 7.1+, `Model.remove_connection` foi depreciado para modelos que não são o `connection_class` primário. Para modelos excluded, a abordagem deve mudar.

**Arquivos afetados:**
- `spec/support/setup.rb` (linha 35)
- `spec/spec_helper.rb` (linha 14)
- `spec/examples/schema_adapter_examples.rb` (linha 22)
- `spec/examples/connection_adapter_examples.rb` (linha 13)
- `spec/tenant_spec.rb` (linha 143)
- `spec/adapters/mysql2_adapter_spec.rb` (linha 39)

**Antes:**
```ruby
Apartment.connection_class.remove_connection(klass)
# ou
excluded_model.constantize.remove_connection
```

**Depois:**
```ruby
klass.connection_handler.remove_connection_pool(klass.connection_specification_name)
# ou de forma simplificada:
klass.remove_connection
```

**Nota:** `remove_connection` sem argumento em uma classe que não é `ActiveRecord::Base` ainda funciona no Rails 7+. A versão com argumento (`remove_connection(klass)` chamada em outra classe) é que muda. Testar qual forma funciona na versão alvo.

### Passo 3.13 — Atualizar `clear_all_connections!` com keyword args

**Por quê:** No Rails 7.1+, `clear_all_connections!` pode receber keyword argument `disconnect`.

**Arquivos afetados:**
- `spec/support/setup.rb` (linhas 30, 36)
- `spec/spec_helper.rb` (linha 15)

**Ação:** Manter como está — `clear_all_connections!` sem argumentos continua funcionando no Rails 7+/8+.

---

## Fase 4 — Correções Internas do Adapter

### Passo 4.1 — Corrigir acesso a `@config` internals no SQLite adapter

**Por quê:** `Apartment.connection.instance_variable_get(:@config)` acessa internals do ActiveRecord que mudaram. No Rails 7+, a config está em `connection.pool.db_config`.

**Arquivo:** `lib/apartment/adapters/sqlite3_adapter.rb`

**Antes (linha 26):**
```ruby
def current
  File.basename(Apartment.connection.instance_variable_get(:@config)[:database], '.sqlite3')
end
```

**Depois:**
```ruby
def current
  File.basename(Apartment.connection.pool.db_config.database, '.sqlite3')
end
```

### Passo 4.2 — Corrigir `silence_warnings`

**Por quê:** `silence_warnings` do ActiveSupport ainda existe no Rails 7+, mas pode ter comportamento diferente. No Ruby 3+, `Kernel#silence_warnings` pode ser usado via `require 'active_support/core_ext/kernel/reporting'`.

**Arquivos afetados:**
- `lib/apartment/adapters/abstract_adapter.rb` (linha 119)
- `spec/support/apartment_helpers.rb` (linha 31)
- `spec/spec_helper.rb` (linha 25)

**Ação:** Manter o uso de `silence_warnings` — ele ainda funciona com Rails 7+/8+ via ActiveSupport. Apenas garantir que `require 'active_support/core_ext/kernel/reporting'` está disponível.

### Passo 4.3 — Corrigir `Apartment.connection.active?` após `establish_connection`

**Por quê:** No Rails 7+, `establish_connection` pode não conectar imediatamente. `connection.active?` pode lançar exceção diferente.

**Arquivo:** `lib/apartment/adapters/abstract_adapter.rb`

**Antes (linhas 174-179):**
```ruby
def connect_to_new(tenant)
  query_cache_enabled = ActiveRecord::Base.connection.query_cache_enabled

  Apartment.establish_connection multi_tenantify(tenant)
  Apartment.connection.active?

  Apartment.connection.enable_query_cache! if query_cache_enabled
```

**Depois:**
```ruby
def connect_to_new(tenant)
  query_cache_enabled = ActiveRecord::Base.connection.query_cache_enabled

  Apartment.establish_connection multi_tenantify(tenant).symbolize_keys
  Apartment.connection.verify!

  Apartment.connection.enable_query_cache! if query_cache_enabled
```

**Nota:** `verify!` é mais robusto que `active?` — reconecta se necessário e levanta exceção se falhar.

---

## Fase 5 — Dummy App e Infraestrutura de Testes

### Passo 5.1 — Modernizar a dummy application

**Por quê:** A dummy app em `spec/dummy/` precisa ser compatível com Rails 7+/8+.

#### 5.1.1 — `spec/dummy/config/application.rb`

**Antes:**
```ruby
require File.expand_path('../boot', __FILE__)

require "active_model/railtie"
require "active_record/railtie"
require "action_controller/railtie"
require "action_view/railtie"
require "action_mailer/railtie"

Bundler.require
require "apartment"

module Dummy
  class Application < Rails::Application
    require 'apartment/elevators/subdomain'
    require 'apartment/elevators/domain'
    config.middleware.use Apartment::Elevators::Subdomain
    config.autoload_paths += %W(#{config.root}/lib)
    config.encoding = "utf-8"
    config.filter_parameters += [:password]
  end
end
```

**Depois:**
```ruby
require_relative "boot"

require "active_model/railtie"
require "active_record/railtie"
require "action_controller/railtie"
require "action_view/railtie"
require "action_mailer/railtie"

Bundler.require
require "apartment"

module Dummy
  class Application < Rails::Application
    config.load_defaults Rails::VERSION::STRING.to_f

    require 'apartment/elevators/subdomain'
    require 'apartment/elevators/domain'
    config.middleware.use Apartment::Elevators::Subdomain
    config.encoding = "utf-8"
    config.filter_parameters += [:password]
  end
end
```

#### 5.1.2 — `spec/dummy/config/boot.rb`

**Antes:**
```ruby
require 'rubygems'
gemfile = File.expand_path('../../../../Gemfile', __FILE__)
if File.exist?(gemfile)
  ENV['BUNDLE_GEMFILE'] = gemfile
  require 'bundler'
  Bundler.setup
end
$:.unshift File.expand_path('../../../../lib', __FILE__)
```

**Depois:**
```ruby
ENV['BUNDLE_GEMFILE'] ||= File.expand_path('../../../../Gemfile', __FILE__)
require 'bundler/setup'
$:.unshift File.expand_path('../../../../lib', __FILE__)
```

#### 5.1.3 — `spec/dummy/config/environment.rb`

**Antes:**
```ruby
require File.expand_path('../application', __FILE__)
Dummy::Application.initialize!
```

**Depois:**
```ruby
require_relative "application"
Dummy::Application.initialize!
```

### Passo 5.2 — Atualizar spec_helper para Rails 7+

**Arquivo:** `spec/spec_helper.rb`

**Antes (linha 25):**
```ruby
silence_warnings{ IRB = Pry }
```

**Depois:**
```ruby
begin
  require 'pry'
  silence_warnings { IRB = Pry } if defined?(Pry)
rescue LoadError
  # Pry not available
end
```

**Nota:** Este bloco já tem rescue, mas o `silence_warnings` dentro dele pode falhar se Pry não estiver carregado. Ajustar.

### Passo 5.3 — Atualizar migrator specs

**Arquivo:** `spec/unit/migrator_spec.rb`

**Por quê:** Remover o contexto `activerecord_below_5_2?` e manter apenas o path de `MigrationContext`.

**Antes:**
```ruby
context "with ActiveRecord below 5.2.0", skip: ... do
  # ...testes com ActiveRecord::Migrator...
end

context "with ActiveRecord above or equal to 5.2.0", skip: ... do
  # ...testes com MigrationContext...
end
```

**Depois:** Manter apenas o contexto `MigrationContext`:
```ruby
describe Apartment::Migrator do
  let(:tenant) { Apartment::Test.next_db }

  before { allow(Apartment::Tenant.adapter).to receive(:connect_to_new) }

  describe "::migrate" do
    it "switches and migrates" do
      expect(Apartment::Tenant).to receive(:switch).with(tenant).and_call_original
      expect_any_instance_of(ActiveRecord::MigrationContext).to receive(:migrate)

      Apartment::Migrator.migrate(tenant)
    end
  end

  describe "::run" do
    it "switches and runs" do
      expect(Apartment::Tenant).to receive(:switch).with(tenant).and_call_original
      expect_any_instance_of(ActiveRecord::MigrationContext).to receive(:run).with(:up, 1234)

      Apartment::Migrator.run(:up, tenant, 1234)
    end
  end

  describe "::rollback" do
    it "switches and rolls back" do
      expect(Apartment::Tenant).to receive(:switch).with(tenant).and_call_original
      expect_any_instance_of(ActiveRecord::MigrationContext).to receive(:rollback).with(2)

      Apartment::Migrator.rollback(tenant, 2)
    end
  end
end
```

### Passo 5.4 — Atualizar integration spec de rake

**Arquivo:** `spec/integration/apartment_rake_integration_spec.rb`

Remover o contexto `"with ActiveRecord below 5.2.0"` e manter apenas o de `MigrationContext`. Seguir a mesma lógica do passo 5.3.

### Passo 5.5 — Atualizar `spec/support/apartment_helpers.rb`

**Por quê:** Usa `ActiveRecord::Migrator.migrate` e `ActiveRecord::Migrator.migrations_path` diretamente.

**Antes:**
```ruby
def migrate
  ActiveRecord::Migrator.migrate(Rails.root + ActiveRecord::Migrator.migrations_path)
end

def rollback
  ActiveRecord::Migrator.rollback(Rails.root + ActiveRecord::Migrator.migrations_path)
end
```

**Depois:**
```ruby
def migrate
  ActiveRecord::Base.connection.migration_context.migrate
end

def rollback
  ActiveRecord::Base.connection.migration_context.rollback
end
```

### Passo 5.6 — Atualizar Rakefile

**Arquivo:** `Rakefile`

**Antes (linhas 118-128):**
```ruby
def activerecord_below_5_2?
  ActiveRecord.version.release < Gem::Version.new('5.2.0')
end

def migrate
  if activerecord_below_5_2?
    ActiveRecord::Migrator.migrate('spec/dummy/db/migrate')
  else
    ActiveRecord::MigrationContext.new('spec/dummy/db/migrate').migrate
  end
end
```

**Depois:**
```ruby
def migrate
  ActiveRecord::MigrationContext.new('spec/dummy/db/migrate').migrate
end
```

**Nota:** No Rails 7.2+, `MigrationContext.new` com path pode precisar de um `SchemaCache` como segundo argumento. Testar e ajustar se necessário.

Também no Rakefile, corrigir `File.exists?` (linhas 43-44):

**Antes:**
```ruby
FileUtils.copy(apartment_db_file + '.sample', apartment_db_file, :verbose => true) unless File.exists?(apartment_db_file)
FileUtils.copy(rails_db_file + '.sample', rails_db_file, :verbose => true) unless File.exists?(rails_db_file)
```

**Depois:**
```ruby
FileUtils.copy(apartment_db_file + '.sample', apartment_db_file, verbose: true) unless File.exist?(apartment_db_file)
FileUtils.copy(rails_db_file + '.sample', rails_db_file, verbose: true) unless File.exist?(rails_db_file)
```

### Passo 5.7 — Corrigir `mock_model` nos testes

**Por quê:** `mock_model` não existe mais no RSpec 3+ sem a gem `rspec-activemodel-mocks`.

**Arquivo:** `spec/support/contexts.rb`

**Antes:**
```ruby
let(:company1) { mock_model(Company, database: db1).as_null_object }
let(:company2) { mock_model(Company, database: db2).as_null_object }
```

**Depois (opção 1 — adicionar gem):**
Adicionar ao gemspec:
```ruby
s.add_development_dependency 'rspec-activemodel-mocks'
```

**Depois (opção 2 — usar instance_double):**
```ruby
let(:company1) { instance_double(Company, database: db1) }
let(:company2) { instance_double(Company, database: db2) }
```

### Passo 5.8 — Corrigir `to_prepare_blocks` nos specs

**Por quê:** `Apartment::Railtie.config.to_prepare_blocks` pode não existir no Rails 7+. No Rails 7+, `to_prepare` usa `ActiveSupport::Reloader`.

**Arquivo:** `spec/examples/generic_adapter_examples.rb` (linha 18)

**Antes:**
```ruby
Apartment::Railtie.config.to_prepare_blocks.map(&:call)
```

**Depois:**
```ruby
Rails.application.reloader.prepare!
```

### Passo 5.9 — Corrigir acesso ao connection pool internals

**Por quê:** `connection_pool.instance_variable_get(:@available).instance_variable_get(:@queue)` acessa internals que mudaram completamente no Rails 7+. O pool usa `ConnectionPool::Queue` diferente.

**Arquivo:** `spec/examples/generic_adapter_examples.rb` (linhas 20-23)

**Antes:**
```ruby
num_available_connections = Apartment.connection_class.connection_pool
  .instance_variable_get(:@available)
  .instance_variable_get(:@queue)
  .size
```

**Depois:**
```ruby
pool = Apartment.connection_class.connection_pool
num_available_connections = pool.size - pool.connections.count(&:in_use?)
```

Ou simplesmente:
```ruby
expect(Apartment.connection_class.connection_pool.connections.size).to be <= 1
```

---

## Fase 6 — Limpeza e Remoção de Código Legado

### Passo 6.1 — Remover suporte a Rails < 7

Remover todas as condicionais de versão:
- `activerecord_below_5_2?` em `lib/apartment/migrator.rb`
- `Rails::VERSION::MAJOR < 4` em `spec/examples/generic_adapter_examples.rb`
- Condicionais JDBC/JRuby (se não necessários)

### Passo 6.2 — Remover adapters não utilizados (opcional)

Se o foco é apenas PostgreSQL 15+, considerar remover:
- `lib/apartment/adapters/sqlite3_adapter.rb`
- `lib/apartment/adapters/mysql2_adapter.rb`
- `lib/apartment/adapters/abstract_jdbc_adapter.rb`
- `lib/apartment/adapters/jdbc_postgresql_adapter.rb`
- `lib/apartment/adapters/jdbc_mysql_adapter.rb`
- Specs correspondentes

### Passo 6.3 — Remover gemfiles antigos

Deletar:
- `gemfiles/rails_4_2.gemfile`
- `gemfiles/rails_5_0.gemfile`
- `gemfiles/rails_5_1.gemfile`
- `gemfiles/rails_5_2.gemfile`
- `gemfiles/rails_6_0.gemfile`
- `gemfiles/rails_master.gemfile`

Executar `bundle exec appraisal generate` para regenerar com os novos Appraisals.

### Passo 6.4 — Atualizar badges e CI

**Arquivo:** `README.md`

- Remover badges do Travis CI (descontinuado)
- Adicionar badges do GitHub Actions (se configurar CI)

---

## Fase 7 — Verificação e Testes

### Passo 7.1 — Rodar bundle install

```bash
bundle install
```

Se houver conflitos de versão, ajustar restrições no gemspec.

### Passo 7.2 — Rodar specs unitários

```bash
bundle exec rspec spec/unit/
```

Corrigir falhas uma por uma. Os unitários não dependem de banco de dados.

### Passo 7.3 — Preparar banco de teste

```bash
rake db:copy_credentials
# Editar spec/config/database.yml e spec/dummy/config/database.yml para PostgreSQL 15+
rake db:test:prepare
```

### Passo 7.4 — Rodar specs de adapter PostgreSQL

```bash
bundle exec rspec spec/adapters/postgresql_adapter_spec.rb
```

### Passo 7.5 — Rodar specs de integração

```bash
bundle exec rspec spec/integration/
```

### Passo 7.6 — Rodar suite completa

```bash
bundle exec rspec
```

### Passo 7.7 — Testar com Appraisals

```bash
bundle exec appraisal install
bundle exec appraisal rspec
```

---

## Resumo — Checklist de Alterações por Arquivo

| # | Arquivo | Alterações |
|---|---|---|
| 1 | `apartment.gemspec` | Atualizar versões de dependências |
| 2 | `Gemfile` | Atualizar versão mínima do Rails |
| 3 | `Appraisals` | Remover Rails antigos, adicionar 7.x/8.x |
| 4 | `lib/apartment/version.rb` | Bump para 3.0.0 |
| 5 | `lib/apartment.rb` | Substituir `connection_config` delegator por wrapper |
| 6 | `lib/apartment/tenant.rb` | `.dup` no config hash |
| 7 | `lib/apartment/migrator.rb` | Remover branch `< 5.2`, usar apenas `migration_context` |
| 8 | `lib/apartment/railtie.rb` | Remover `Migrator.migrations_paths =` |
| 9 | `lib/apartment/console.rb` | Substituir `ActionDispatch::Callbacks` |
| 10 | `lib/apartment/adapters/abstract_adapter.rb` | `File.exist?`, `symbolize_keys`, `verify!` |
| 11 | `lib/apartment/adapters/postgresql_adapter.rb` | Remover workaround PG < 9.3, remover `postgresql_version` |
| 12 | `lib/apartment/adapters/sqlite3_adapter.rb` | `File.exist?`, `pool.db_config.database` |
| 13 | `lib/apartment/adapters/mysql2_adapter.rb` | (sem alterações críticas) |
| 14 | `Rakefile` | `File.exist?`, remover `activerecord_below_5_2?`, modernizar `migrate` |
| 15 | `spec/spec_helper.rb` | Ajustar `silence_warnings`/Pry block |
| 16 | `spec/support/config.rb` | `YAML.safe_load` |
| 17 | `spec/support/setup.rb` | Remover `database_configuration = {}` |
| 18 | `spec/support/contexts.rb` | Substituir `mock_model` |
| 19 | `spec/support/apartment_helpers.rb` | Usar `migration_context` |
| 20 | `spec/unit/migrator_spec.rb` | Remover contexto `< 5.2` |
| 21 | `spec/integration/apartment_rake_integration_spec.rb` | Remover contexto `< 5.2` |
| 22 | `spec/examples/generic_adapter_examples.rb` | Corrigir pool internals, `to_prepare_blocks`, versão guard |
| 23 | `spec/schemas/v1.rb`, `v2.rb`, `v3.rb` | `ActiveRecord::Schema[7.1].define` |
| 24 | `spec/dummy/db/schema.rb` | `ActiveRecord::Schema[7.1].define` |
| 25 | `spec/dummy/config/application.rb` | `require_relative`, `load_defaults`, remover `autoload_paths` |
| 26 | `spec/dummy/config/boot.rb` | Simplificar setup do Bundler |
| 27 | `spec/dummy/config/environment.rb` | `require_relative` |
| 28 | `spec/dummy/config/environments/test.rb` | `show_exceptions = :none` |
| 29 | `spec/dummy/config/initializers/secret_token.rb` | Renomear e usar `secret_key_base` |
| 30 | `spec/adapters/sqlite3_adapter_spec.rb` | `File.exist?` |
| 31 | `gemfiles/*` | Deletar antigos, regenerar |

---

## Ordem de Execução Recomendada

1. **Fase 1** — Dependências (gemspec, Gemfile, Appraisals, version)
2. **Fase 2** — Ruby 3.x (File.exist?, YAML.safe_load)
3. **Fase 3** — Rails 7+ APIs (connection_config, Migrator, Railtie, console, Schema.define, show_exceptions, secret_key_base)
4. **Fase 4** — Adapter internals (SQLite @config, silence_warnings, verify!)
5. **Fase 5** — Testes (dummy app, spec_helper, migrator specs, shared examples, Rakefile)
6. **Fase 6** — Limpeza (remover código legado, adapters desnecessários, gemfiles antigos)
7. **Fase 7** — Verificação (bundle install → unit specs → adapter specs → integration → appraisals)

**Regra:** Cada fase deve compilar/carregar sem erros antes de passar para a próxima. A Fase 7 é iterativa — fix → test → fix → test.
