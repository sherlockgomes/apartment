# Instruções para Agentes de IA — Projeto Apartment

## Contexto do Projeto

Este é um **fork local** da gem [influitive/apartment](https://github.com/influitive/apartment) v2.2.1, uma biblioteca Ruby para **multitenancy de banco de dados** em aplicações Rails/Rack. O projeto original está inativo desde junho de 2019 e estamos modernizando-o para funcionar com **Ruby 3.3+** e **Rails 8+** com **PostgreSQL 15+**.

A gem isola dados por tenant (inquilino/empresa) usando **schemas PostgreSQL** (modo principal) ou bancos de dados separados, enquanto mantém dados compartilhados em um namespace global (`public`).

---

## Stack Alvo

- **Ruby:** 3.3+
- **Rails:** 8+
- **Banco de dados:** PostgreSQL 15+
- **Idioma das respostas:** pt-BR
- **Idioma do código:** EN (inglês)

---

## Arquitetura — Mapa dos Componentes

### Módulo Principal

- `lib/apartment.rb` — Configuração global da gem (opções: `tenant_names`, `excluded_models`, `use_schemas`, `default_schema`, `persistent_schemas`, etc.)
- `lib/apartment/tenant.rb` — Entry point da API pública. Delega para o adapter via `Thread.current[:apartment_adapter]`. Métodos: `create`, `drop`, `switch`, `switch!`, `current`, `reset`, `each`, `seed`, `init`.
- `lib/apartment/version.rb` — Versão da gem.

### Adapters (`lib/apartment/adapters/`)

Implementam a lógica de multitenancy para cada banco de dados. Hierarquia:

```
AbstractAdapter (base — callbacks, ciclo de vida, excluded models)
├── PostgresqlAdapter (DB separado por tenant)
│   └── PostgresqlSchemaAdapter (schema_search_path — MODO PRINCIPAL)
│       └── PostgresqlSchemaFromSqlAdapter (criação via pg_dump)
├── Mysql2Adapter → Mysql2SchemaAdapter
├── Sqlite3Adapter
├── AbstractJDBCAdapter → JDBCMysqlAdapter
├── JDBCPostgresqlAdapter → JDBCPostgresqlSchemaAdapter
└── PostgisAdapter (delegate para PostgresqlAdapter)
```

**Foco do upgrade:** `AbstractAdapter` e as três variantes de `PostgresqlAdapter`. Os adapters JDBC, MySQL e SQLite são secundários.

### Elevators (`lib/apartment/elevators/`)

Rack middlewares que determinam o tenant a partir do request HTTP:

- `Generic` — Base. Aceita `Proc` ou método `parse_tenant_name`.
- `Subdomain` — Usa `public_suffix` para extrair subdomínio.
- `FirstSubdomain` — Primeiro subdomínio da cadeia.
- `Domain` — Second-level domain (ignora www).
- `Host` — Host completo com subdomínios ignoráveis.
- `HostHash` — Mapeamento hash host→tenant.

### Integração Rails

- `lib/apartment/railtie.rb` — Railtie: configura defaults, inicializa excluded models (`to_prepare`), carrega rake tasks, adiciona `Reloader` middleware em development.
- `lib/apartment/migrator.rb` — Executa migrações no contexto de cada tenant.
- `lib/apartment/reloader.rb` — Middleware de development para reinicializar table names.
- `lib/apartment/console.rb` — Override de `reload!` no console Rails.
- `lib/apartment/tasks/enhancements.rb` — Estende rake tasks do Rails (`db:migrate` → `apartment:migrate`, etc.).
- `lib/tasks/apartment.rake` — Tasks: `apartment:create`, `apartment:drop`, `apartment:migrate`, `apartment:seed`, `apartment:rollback`.

### Generator

- `lib/generators/apartment/install/` — `rails g apartment:install` cria `config/initializers/apartment.rb`.

---

## Regras para Edição de Código

### Prioridades

1. **Foco em PostgreSQL schemas** — É o modo principal (`use_schemas = true`). Priorize `PostgresqlSchemaAdapter` e `PostgresqlSchemaFromSqlAdapter` sobre outros adapters.
2. **Manter compatibilidade da API pública** — `Apartment::Tenant.create`, `.drop`, `.switch`, `.switch!`, `.current`, `.reset` devem manter as mesmas assinaturas.
3. **Não alterar o comportamento de multitenancy** — A lógica de isolamento por schema/database deve permanecer intacta.
4. **Preservar callbacks** — `before_create`, `after_create`, `before_switch`, `after_switch` são usados por consumidores da gem.

### APIs Depreciadas a Substituir

| Antigo (Rails < 6.1) | Novo (Rails 7+/8+) | Arquivos afetados |
|---|---|---|
| `connection_config` | `connection_db_config.configuration_hash` | `lib/apartment.rb`, `lib/apartment/tenant.rb` |
| `File.exists?` | `File.exist?` | `lib/apartment/adapters/abstract_adapter.rb`, `lib/apartment/adapters/sqlite3_adapter.rb` |
| `ActiveRecord::Migrator.migrate(paths)` | `ActiveRecord::Base.connection.migration_context.migrate` | `lib/apartment/migrator.rb` |
| `ActiveRecord::Migrator.migrations_paths` | `ActiveRecord::Migrator.migrations_paths` (ainda existe, mas uso mudou) | `lib/apartment/railtie.rb` |
| `silence_warnings` (de ActiveSupport) | `Kernel.silence_warnings` ou `Warning[]` | `lib/apartment/adapters/abstract_adapter.rb`, `spec/support/apartment_helpers.rb` |
| `send(:postgresql_version)` (privado) | `postgresql_version` (público desde Rails 5.0) | `lib/apartment/adapters/postgresql_adapter.rb` |

### Padrões a Seguir

- **Thread-safety:** O adapter é armazenado em `Thread.current[:apartment_adapter]`. Manter esse padrão.
- **Callbacks:** Usar `ActiveSupport::Callbacks` com `define_callbacks` e `run_callbacks`.
- **Exceções:** Usar a hierarquia existente: `ApartmentError` → `TenantNotFound`, `TenantExists`, `AdapterNotFound`, `FileNotFound`.
- **Naming:** Métodos internos em inglês, snake_case. Tenant names são strings.
- **SQL seguro:** Sempre usar `quote_table_name` ou aspas escapadas para nomes de tenant em SQL. Não interpolar diretamente.

### O que NÃO fazer

- **Não remover suporte a excluded models** — Modelos globais (como `Company`, `User`) que ficam no schema `public` são fundamentais.
- **Não alterar a assinatura dos Elevators** — Eles são Rack middlewares; `initialize(app, ...)` e `call(env)` devem permanecer.
- **Não misturar lógica de adapter** — Cada adapter é independente. Não colocar lógica PostgreSQL no abstract adapter.
- **Não ignorar `persistent_schemas`** — Schemas como `shared_extensions` (para hstore, uuid-ossp) devem sempre estar no `search_path`.
- **Não remover testes existentes** — A suite tem ~2.953 linhas e ratio 2:1. Ao alterar funcionalidade, atualize o teste correspondente.

---

## Estrutura de Testes

### Como Rodar

```bash
# Setup (copia credenciais e cria bancos de teste)
rake db:copy_credentials db:test:prepare

# Rodar toda a suite
rake spec

# Rodar por categoria
rake spec:unit        # Testes unitários
rake spec:adapters    # Testes de adapters
rake spec:integration # Testes de integração
rake spec:tasks       # Testes de rake tasks
```

### Organização

| Diretório | Conteúdo |
|---|---|
| `spec/unit/` | Testes unitários de elevators, config, migrator, reloader |
| `spec/adapters/` | Testes por adapter (postgresql, mysql2, sqlite3, jdbc) |
| `spec/integration/` | Rake tasks, query caching, uso em engines |
| `spec/tasks/` | Testes de rake tasks do apartment |
| `spec/examples/` | Shared examples (`schema_adapter_examples`, `generic_adapter_examples`, etc.) |
| `spec/schemas/` | Versões de schema (v1, v2, v3) para testes de migração |
| `spec/support/` | Helpers: `setup.rb` (around hook), `config.rb` (YAML), `contexts.rb` (shared contexts), `apartment_helpers.rb` |
| `spec/dummy/` | App Rails completa para testes (models: User, Company) |
| `spec/dummy_engine/` | Engine Rails para teste de integração |

### Padrões nos Testes

- **Tenants de teste:** Criados via `Apartment::Test.next_db` (gera `db1`, `db2`, etc.) — são schemas temporários.
- **Around hook:** Cada spec recria o adapter e limpa tudo depois (`spec/support/setup.rb`).
- **Shared examples:** Em `spec/examples/`. Use `it_behaves_like` para reusar testes entre adapters.
- **Shared contexts:** `"with default schema"`, `"elevators"`, `"persistent_schemas"` em `spec/support/contexts.rb`.
- **Config de DB:** Em `spec/config/database.yml` (copiar de `database.yml.sample`).

### Ao Criar/Editar Testes

- Use `let(:db1)` e `let(:db2)` já definidos pelo `Setup` module.
- Crie schemas com `Apartment::Test.create_schema(name)` para testes rápidos sem import de schema.rb.
- Use `Apartment::Tenant.switch(tenant) { ... }` para testar operações dentro de um tenant.
- Sempre limpe schemas criados no `after` block.

---

## Fluxos Críticos

### Switch de Tenant (PostgreSQL Schema)

```
Apartment::Tenant.switch("acme") { ... }
  → adapter.switch!("acme")
    → run_callbacks(:switch)
    → connect_to_new("acme")
      → verifica schema_exists?("acme")
      → @current = "acme"
      → connection.schema_search_path = '"acme", "public"'  (+ persistent_schemas)
    → clear_query_cache
  → yield (bloco executado no contexto do tenant)
  → switch!(previous_tenant)  # restaura
```

### Criação de Tenant

```
Apartment::Tenant.create("acme")
  → run_callbacks(:create)
  → CREATE SCHEMA "acme"
  → switch("acme")
    → load(db/schema.rb) OU pg_dump + clone
    → seed_data (se seed_after_create)
  → switch back
```

### Elevators (request HTTP)

```
Request → Elevator.call(env)
  → parse_tenant_name(request) → "acme"
  → Apartment::Tenant.switch("acme") { @app.call(env) }
  → tenant automaticamente restaurado após request
```

---

## Configurações Importantes

### Opções Mais Usadas

```ruby
Apartment.configure do |config|
  config.excluded_models = ["Company", "User"]   # Models no schema público
  config.tenant_names = -> { Company.pluck(:database) }  # Lista dinâmica
  config.use_schemas = true                       # Schemas PostgreSQL (padrão)
  config.default_schema = "public"                # Schema padrão
  config.persistent_schemas = ["shared_extensions"] # Sempre no search_path
  config.seed_after_create = false                # Seeds ao criar tenant
  config.db_migrate_tenants = true                # db:migrate migra tenants
  config.parallel_migration_threads = 0           # 0 = sem paralelismo
end
```

### Variáveis de Ambiente nos Testes

- `DB` — Lista de tenants para migrar (separados por vírgula)
- `VERSION` — Versão de migration para migrate:up/down
- `STEP` — Número de steps para rollback
- `IGNORE_EMPTY_TENANTS` — Suprimir warning de tenants vazios

---

## Problemas Conhecidos no Upgrade para Rails 8+

Consulte `ANALYZE.MD` seção 8 para a lista completa. Os mais críticos:

1. **`activerecord >= 3.1.2, < 6.1`** no gemspec — Precisa ser `>= 7.2` ou similar.
2. **`connection_config`** depreciado — Substituir por `connection_db_config.configuration_hash`.
3. **`File.exists?`** removido no Ruby 3.2+ — Substituir por `File.exist?`.
4. **API de migrações** mudou no Rails 7+/8+ — `MigrationContext` obrigatório.
5. **`establish_connection`** mudou a assinatura no Rails 7+.
6. **Multi-database nativo** do Rails 6+ pode conflitar.

---

## Referências Rápidas

| O que | Onde |
|---|---|
| Configuração da gem | `lib/apartment.rb` |
| API pública (Tenant) | `lib/apartment/tenant.rb` |
| Adapter base | `lib/apartment/adapters/abstract_adapter.rb` |
| Adapter PostgreSQL (schemas) | `lib/apartment/adapters/postgresql_adapter.rb` |
| Elevators | `lib/apartment/elevators/*.rb` |
| Rake tasks | `lib/tasks/apartment.rake` |
| Rake task enhancements | `lib/apartment/tasks/enhancements.rb` |
| Railtie | `lib/apartment/railtie.rb` |
| Migrator | `lib/apartment/migrator.rb` |
| Gemspec | `apartment.gemspec` |
| Template do initializer | `lib/generators/apartment/install/templates/apartment.rb` |
| Análise completa | `ANALYZE.MD` |
| Passos de upgrade | `RUBY-UPGRADE-STEPS.MD` |
| Spec helpers | `spec/support/setup.rb`, `spec/support/apartment_helpers.rb` |
| Shared examples | `spec/examples/*.rb` |
| Dummy app | `spec/dummy/` |
