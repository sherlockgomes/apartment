# Análise Detalhada do Projeto Apartment

## 1. Visão Geral

**Nome:** Apartment
**Versão:** 2.2.1
**Licença:** MIT
**Autores:** Ryan Brunner e Brad Robertson (Influitive)
**Repositório:** https://github.com/influitive/apartment
**Primeiro commit:** 29/11/2010
**Último commit:** 25/06/2019
**Total de commits:** 760
**Descrição:** Gem Ruby para gerenciamento de multitenancy (multi-inquilinos) em aplicações Rails/Rack com ActiveRecord.

### Propósito

O Apartment permite que aplicações Rails lidem com **multitenancy de banco de dados**, isolando dados por tenant (inquilino/empresa) enquanto mantém dados compartilhados em um namespace global (público). Ele suporta duas estratégias principais:

1. **Schema-based** (PostgreSQL): Cada tenant é um schema separado no mesmo banco de dados
2. **Database-based**: Cada tenant é um banco de dados separado

---

## 2. Estatísticas do Código

| Métrica | Valor |
|---|---|
| Arquivos Ruby no `lib/` | 25 |
| Linhas de código no `lib/` | ~1.444 |
| Arquivos de spec (`*_spec.rb`) | 20 |
| Linhas de código nos specs | ~2.953 |
| Total de arquivos Ruby | 101 |
| Ratio teste/código | ~2:1 |

---

## 3. Arquitetura

### 3.1 Estrutura de Diretórios

```
lib/
├── apartment.rb                          # Módulo principal, configuração
├── apartment/
│   ├── version.rb                        # Versão da gem (2.2.1)
│   ├── tenant.rb                         # Entry point principal - delegates para adapter
│   ├── railtie.rb                        # Integração com Rails
│   ├── migrator.rb                       # Gerenciamento de migrações por tenant
│   ├── reloader.rb                       # Middleware para dev (reinicialização)
│   ├── console.rb                        # Override de reload! no console
│   ├── deprecation.rb                    # Helper de depreciação
│   ├── adapters/
│   │   ├── abstract_adapter.rb           # Adapter base com lógica compartilhada
│   │   ├── postgresql_adapter.rb         # PostgreSQL (DB + Schema + SQL)
│   │   ├── postgis_adapter.rb            # PostGIS (delegate para PostgreSQL)
│   │   ├── mysql2_adapter.rb             # MySQL2 (DB + Schema)
│   │   ├── sqlite3_adapter.rb            # SQLite3
│   │   ├── abstract_jdbc_adapter.rb      # Base JDBC
│   │   ├── jdbc_postgresql_adapter.rb    # JDBC PostgreSQL (JRuby)
│   │   └── jdbc_mysql_adapter.rb         # JDBC MySQL (JRuby)
│   ├── elevators/
│   │   ├── generic.rb                    # Elevator base (Rack middleware)
│   │   ├── subdomain.rb                  # Switch por subdomain
│   │   ├── first_subdomain.rb            # Switch pelo 1º subdomain
│   │   ├── domain.rb                     # Switch por domínio
│   │   ├── host.rb                       # Switch por host completo
│   │   └── host_hash.rb                  # Switch por hash host->tenant
│   └── tasks/
│       └── enhancements.rb               # Enhance de Rake tasks do Rails
├── tasks/
│   └── apartment.rake                    # Rake tasks customizadas
└── generators/
    └── apartment/install/                # Generator rails g apartment:install
        ├── install_generator.rb
        ├── templates/apartment.rb
        └── USAGE
```

### 3.2 Diagrama de Dependências Internas

```
Apartment (módulo principal - configuração)
    └── Apartment::Tenant (entry point, delegates para adapter)
            └── Apartment::Adapters::AbstractAdapter (base)
                    ├── PostgresqlAdapter (DB separado)
                    │   └── PostgresqlSchemaAdapter (schemas)
                    │       └── PostgresqlSchemaFromSqlAdapter (schemas via SQL dump)
                    ├── Mysql2Adapter (DB separado)
                    │   └── Mysql2SchemaAdapter (USE statement)
                    ├── Sqlite3Adapter (arquivo por tenant)
                    ├── AbstractJDBCAdapter (JRuby base)
                    │   └── JDBCMysqlAdapter
                    ├── JDBCPostgresqlAdapter
                    └── JDBCPostgresqlSchemaAdapter

Apartment::Elevators::Generic (Rack middleware base)
    ├── Subdomain
    │   └── FirstSubdomain
    ├── Domain
    ├── Host
    └── HostHash
```

---

## 4. Componentes Principais

### 4.1 Módulo `Apartment` (`lib/apartment.rb`)

Centro de configuração da gem. Define todas as opções configuráveis via `Apartment.configure`:

| Opção | Tipo | Default | Descrição |
|---|---|---|---|
| `tenant_names` | Array/Hash/Proc | `[]` | Lista de tenants para migração |
| `excluded_models` | Array<String> | `[]` | Models que permanecem no schema público |
| `default_schema` | String | `"public"` | Schema padrão (PostgreSQL-specific) |
| `use_schemas` | Boolean | `true` | Usar schemas em vez de DBs separados |
| `use_sql` | Boolean | `false` | Usar pg_dump para criar schemas |
| `seed_after_create` | Boolean | `false` | Executar seeds ao criar tenant |
| `prepend_environment` | Boolean | `false` | Prefixar environment no nome do tenant |
| `append_environment` | Boolean | `false` | Sufixar environment no nome do tenant |
| `persistent_schemas` | Array | `[]` | Schemas sempre no search_path |
| `parallel_migration_threads` | Integer | `0` | Threads para migrações paralelas |
| `with_multi_server_setup` | Boolean | `false` | Tenants em servidores diferentes |
| `connection_class` | Class | `ActiveRecord::Base` | Classe de conexão base |
| `pg_excluded_names` | Array | `[]` | Nomes a não substituir no SQL dump |
| `database_schema_file` | String | `db/schema.rb` | Arquivo de schema |
| `seed_data_file` | String | `db/seeds.rb` | Arquivo de seeds |
| `db_migrate_tenants` | Boolean | `true` | Migrar tenants com db:migrate |
| `tld_length` | Integer | - | Tamanho do TLD |

**Exceções definidas:**
- `ApartmentError` — base
- `AdapterNotFound` — adapter não encontrado
- `FileNotFound` — arquivo não encontrado
- `TenantNotFound` — tenant não existe
- `TenantExists` — tenant já existe

### 4.2 `Apartment::Tenant` (`lib/apartment/tenant.rb`)

Entry point principal da gem. Usa padrão **Delegate** para delegar todas as operações ao adapter correto:

- `create(tenant)` — cria um novo tenant
- `drop(tenant)` — remove um tenant
- `switch(tenant) { block }` — troca para tenant dentro de um bloco
- `switch!(tenant)` — troca para tenant sem bloco (não recomendado)
- `current` — retorna o tenant atual
- `reset` — volta ao tenant padrão
- `each(tenants)` — itera sobre tenants
- `seed` — executa seed data
- `init` — inicializa excluded models

O adapter é **thread-safe** — armazenado em `Thread.current[:apartment_adapter]`. A seleção do adapter é feita dinamicamente baseada no `config[:adapter]` do banco de dados.

### 4.3 Adapters

#### 4.3.1 `AbstractAdapter` (`lib/apartment/adapters/abstract_adapter.rb`)

Classe base com **270 linhas**. Implementa:

- **Callbacks** via `ActiveSupport::Callbacks` — `:create` e `:switch`
- **Ciclo de vida do tenant**: create → import_schema → seed → switch
- **Pattern `switch`**: salva tenant anterior → troca → executa bloco → restaura
- **Multi-server**: `SeparateDbConnectionHandler` para conexões neutras
- **Excluded models**: estabelece conexão separada para models globais

#### 4.3.2 `PostgresqlAdapter` — Três variantes:

1. **`PostgresqlAdapter`** — Cria bancos de dados separados (básico)
2. **`PostgresqlSchemaAdapter`** — Usa `schema_search_path` do PostgreSQL (recomendado)
   - `connect_to_new` modifica `schema_search_path`
   - `persistent_schemas` são mantidos no path
   - Excluded models recebem prefixo `default_tenant.table_name`
   - Workaround para PostgreSQL < 9.3 (prepared statements)
3. **`PostgresqlSchemaFromSqlAdapter`** — Clona schemas via `pg_dump`
   - Executa `pg_dump -s -x -O` para obter DDL
   - Substitui referências do schema público pelo novo tenant
   - Blacklist de statements (`SET search_path`, `SET lock_timeout`, etc.)
   - Copia `schema_migrations` e `ar_internal_metadata`

#### 4.3.3 `Mysql2Adapter` — Duas variantes:

1. **`Mysql2Adapter`** — Cria bancos de dados separados
2. **`Mysql2SchemaAdapter`** — Usa `USE database` statement para trocar

#### 4.3.4 `Sqlite3Adapter`

- Cria arquivos `.sqlite3` separados por tenant
- Tenant name = nome do arquivo

#### 4.3.5 Adapters JDBC (JRuby)

- `AbstractJDBCAdapter`, `JDBCPostgresqlAdapter`, `JDBCPostgresqlSchemaAdapter`, `JDBCMysqlAdapter`
- Adaptam URLs JDBC para multi-tenancy

### 4.4 Elevators (Rack Middlewares)

Mecanismo de **roteamento automático** de tenant por request HTTP.

#### 4.4.1 `Generic` (base)

```ruby
def call(env)
  request = Rack::Request.new(env)
  database = @processor.call(request)
  if database
    Apartment::Tenant.switch(database) { @app.call(env) }
  else
    @app.call(env)
  end
end
```

- Aceita um `Proc` ou método `parse_tenant_name` para determinar o tenant
- Todo o request é executado dentro de `Apartment::Tenant.switch`

#### 4.4.2 Elevators Disponíveis

| Elevator | Lógica | Exemplo |
|---|---|---|
| `Subdomain` | Primeiro subdomínio (com `public_suffix`) | `acme.app.com` → `acme` |
| `FirstSubdomain` | Primeiro subdomínio da cadeia | `acme.dept.app.com` → `acme` |
| `Domain` | Second-level domain (ignora www) | `www.acme.com` → `acme` |
| `Host` | Host completo (ignora subdomínios configurados) | `acme.app.com` → `acme.app.com` |
| `HostHash` | Mapeamento hash host→tenant | `{'acme.com' => 'acme_tenant'}` |

**Nota:** `Subdomain` usa a gem `public_suffix` para parsing correto de domínios, considerando TLDs complexos (`.co.uk`, `.com.br`, etc.) e excluindo IPs.

### 4.5 Migrator (`lib/apartment/migrator.rb`)

Executa migrações dentro do contexto de cada tenant:

- `migrate(database)` — migra para a versão mais recente
- `run(direction, database, version)` — executa migration específica (up/down)
- `rollback(database, step)` — rollback de N migrações

Suporta tanto ActiveRecord < 5.2 quanto >= 5.2 (usa `migration_context`).

### 4.6 Rake Tasks

#### Tasks do Apartment (`apartment:*`)

| Task | Descrição |
|---|---|
| `apartment:create` | Cria todos os tenants |
| `apartment:drop` | Remove todos os tenants |
| `apartment:migrate` | Migra todos os tenants |
| `apartment:seed` | Executa seeds em todos os tenants |
| `apartment:rollback` | Rollback em todos os tenants |
| `apartment:migrate:up` | Executa migration up em todos os tenants |
| `apartment:migrate:down` | Executa migration down em todos os tenants |
| `apartment:migrate:redo` | Redo em todos os tenants |

#### Enhancements (tasks do Rails estendidas)

Quando `db_migrate_tenants = true`, as seguintes tasks do Rails são automaticamente estendidas:

- **Before**: `db:drop` → `apartment:drop`
- **After**: `db:migrate`, `db:rollback`, `db:migrate:up`, `db:migrate:down`, `db:migrate:redo`, `db:seed` → tasks correspondentes do `apartment:`

Suporta **migrações paralelas** via gem `parallel` (configurável por `parallel_migration_threads`).

### 4.7 Railtie (`lib/apartment/railtie.rb`)

Integração com o ciclo de vida do Rails:

1. **`config.before_initialize`** — Define valores default de configuração
2. **`config.to_prepare`** — Inicializa `Apartment::Tenant.init` (excluded models)
3. **`rake_tasks`** — Carrega tasks e enhancements
4. **Development only**:
   - Adiciona middleware `Apartment::Reloader` para reinicializar table names
   - Override de `reload!` no console para reinicializar Apartment

---

## 5. Dependências

### 5.1 Dependências de Runtime

| Gem | Versão | Uso |
|---|---|---|
| `activerecord` | `>= 3.1.2, < 6.1` | ORM base |
| `rack` | `>= 1.3.6` | Interface web (elevators) |
| `public_suffix` | `>= 2` | Parsing de domínios (subdomains) |
| `parallel` | `>= 0.7.1` | Migrações paralelas |

### 5.2 Dependências de Desenvolvimento

| Gem | Versão | Uso |
|---|---|---|
| `appraisal` | - | Testes com múltiplas versões de Rails |
| `rake` | `~> 0.9` | Task runner |
| `rspec` | `~> 3.4` | Framework de testes |
| `rspec-rails` | `~> 3.4` | Integração RSpec com Rails |
| `capybara` | `~> 2.0` | Testes de integração |
| `bundler` | `>= 1.3, < 2.0` | Gerenciamento de dependências |
| `pg` | - | Driver PostgreSQL |
| `mysql2` | - | Driver MySQL |
| `sqlite3` | `~> 1.3.6` | Driver SQLite |

### 5.3 Compatibilidade Testada (Appraisals)

- Rails 4.2
- Rails 5.0
- Rails 5.1
- Rails 5.2
- Rails 6.0 (rc1)
- Rails master (à época)

---

## 6. Suíte de Testes

### 6.1 Estrutura

```
spec/
├── apartment_spec.rb                  # Teste básico do módulo
├── tenant_spec.rb                     # Testes do Tenant
├── adapters/                          # Testes por adapter
│   ├── postgresql_adapter_spec.rb
│   ├── mysql2_adapter_spec.rb
│   ├── sqlite3_adapter_spec.rb
│   ├── jdbc_postgresql_adapter_spec.rb
│   └── jdbc_mysql_adapter_spec.rb
├── unit/                              # Testes unitários
│   ├── config_spec.rb
│   ├── migrator_spec.rb
│   ├── reloader_spec.rb
│   └── elevators/                     # Testes de cada elevator
│       ├── generic_spec.rb
│       ├── subdomain_spec.rb
│       ├── first_subdomain_spec.rb
│       ├── domain_spec.rb
│       ├── host_spec.rb
│       └── host_hash_spec.rb
├── integration/                       # Testes de integração
│   ├── apartment_rake_integration_spec.rb
│   ├── query_caching_spec.rb
│   └── use_within_an_engine_spec.rb
├── tasks/
│   └── apartment_rake_spec.rb
├── examples/                          # Shared examples
│   ├── schema_adapter_examples.rb
│   ├── generic_adapter_examples.rb
│   ├── generic_adapter_custom_configuration_example.rb
│   └── connection_adapter_examples.rb
├── schemas/                           # Versões de schema para testes
│   ├── v1.rb, v2.rb, v3.rb
├── support/                           # Helpers e configuração
│   ├── setup.rb, config.rb, contexts.rb
│   ├── apartment_helpers.rb
│   ├── requirements.rb
│   └── capybara_sessions.rb
├── dummy/                             # Aplicação Rails dummy para testes
└── dummy_engine/                      # Engine Rails dummy para testes
```

### 6.2 Dummy Application

Aplicação Rails completa em `spec/dummy/` com:
- Models: `User`, `Company` (excluded model)
- Tabelas: `users`, `companies`, `books`, `delayed_jobs`, `public_tokens`
- Company configurada como excluded model (permanece no schema público)
- `tenant_names` dinâmico via `Company.pluck(:database)`

---

## 7. Padrões de Design Identificados

| Padrão | Onde | Descrição |
|---|---|---|
| **Strategy** | Adapters | Cada banco de dados tem seu adapter |
| **Delegate** | Tenant → Adapter | Tenant delega operações ao adapter |
| **Template Method** | AbstractAdapter | Métodos hook para subclasses |
| **Middleware** | Elevators | Rack middleware para roteamento |
| **Factory Method** | `Tenant.adapter` | Criação dinâmica do adapter |
| **Callback** | AbstractAdapter | `ActiveSupport::Callbacks` para create/switch |
| **Thread-Local** | `Thread.current[:apartment_adapter]` | Thread-safety |

---

## 8. Problemas e Limitações Identificados

### 8.1 Problemas Críticos para Upgrade (Rails 8+ / Ruby 3.3+)

1. **Compatibilidade de ActiveRecord limitada a `< 6.1`** — O gemspec restringe `activerecord >= 3.1.2, < 6.1`. Para Rails 8+, essa restrição precisa ser removida e a gem adaptada.

2. **API `connection_config` depreciada** — `Apartment.connection_config` foi depreciada no Rails 6.1+ em favor de `connection_db_config`. Usado em `lib/apartment.rb:19` e `lib/apartment/tenant.rb:63`.

3. **`ActiveRecord::Migrator` API mudou** — O código em `migrator.rb` trata Rails < 5.2 vs >= 5.2, mas Rails 7+ mudou significativamente a API de migrations (uso de `MigrationContext` obrigatório, múltiplos databases nativos).

4. **`File.exists?` removido no Ruby 3.2+** — Usado em `abstract_adapter.rb:212` e `sqlite3_adapter.rb:20,33,40`. Deve ser substituído por `File.exist?`.

5. **`schema_search_path` assignment** — Rails 7+ alterou como o search path é gerenciado internamente.

6. **`silence_warnings` movido** — Em Rails 7.1+ o método foi movido para `Kernel`.

7. **Multi-database nativo do Rails 6+** — Rails 6 introduziu suporte nativo a múltiplos databases, o que pode conflitar com a abordagem do Apartment.

### 8.2 Problemas de Design

1. **Thread-safety parcial** — O adapter é thread-local, mas a configuração (`Apartment.configure`) é global (class-level). Isso pode causar race conditions em ambientes multi-threaded.

2. **Acoplamento com detalhes internos do ActiveRecord** — Uso de `instance_variable_get(:@config)` no SQLite adapter, `send(:postgresql_version)` para acessar método privado, e acesso direto a `schema_search_path=`.

3. **SQL Injection potencial** — Em `drop_command` e `create_tenant_command`, nomes de tenant são interpolados diretamente em SQL (ex: `DROP SCHEMA "#{tenant}" CASCADE`). Embora `quote_table_name` seja usado em alguns lugares, não é consistente.

4. **`has_and_belongs_to_many` não suportado** para excluded models — Limitação documentada, requer `has_many :through`.

5. **Reloader frágil** — O mecanismo de reinicialização em development é descrito pelo próprio autor como "workaround" e "hack", com comentários como "Hope to fix that soon".

6. **Migrações paralelas sem controle de pool** — Embora documentado que `parallel_migration_threads` deve ser menor que o pool size, não há validação disso.

### 8.3 Dívida Técnica

1. **Gemspec com dependências desatualizadas** — `bundler < 2.0`, `rake ~> 0.9` (a versão atual é 13+)
2. **Travis CI** — Badges apontam para Travis CI (descontinuado)
3. **Sem suporte oficial a Rails 7+/8+** — O projeto foi atualizado pela última vez em junho de 2019
4. **Comentários TODO espalhados** — `default_schema` tem TODO sobre ser PostgreSQL-specific, entre outros
5. **Falta de Rubocop/linter** — Não há configuração de linter
6. **Console override invasivo** — Redefine `reload!` globalmente

---

## 9. Fluxo de Operação

### 9.1 Fluxo de Request HTTP (com Elevator)

```
Request HTTP
    │
    ▼
Rack Middleware Stack
    │
    ▼
Apartment::Elevators::Subdomain (ou outro)
    │
    ├── Rack::Request.new(env)
    ├── parse_tenant_name(request) → "tenant_abc"
    │
    ▼
Apartment::Tenant.switch("tenant_abc")
    │
    ├── adapter.switch!("tenant_abc")
    │   ├── run_callbacks(:switch)
    │   ├── connect_to_new("tenant_abc")
    │   │   └── SET search_path = "tenant_abc", public (PostgreSQL Schema)
    │   │   └── OU establish_connection(tenant_db_config) (Database)
    │   └── clear_query_cache
    │
    ▼
@app.call(env)  ← Request executado no contexto do tenant
    │
    ▼
switch!(previous_tenant)  ← Restaura tenant anterior
```

### 9.2 Fluxo de Criação de Tenant

```
Apartment::Tenant.create("new_tenant")
    │
    ├── run_callbacks(:create)
    ├── create_tenant("new_tenant")
    │   ├── with_neutral_connection
    │   │   └── CREATE SCHEMA "new_tenant" (PostgreSQL Schema)
    │   │   └── OU CREATE DATABASE new_tenant (Database)
    │
    ├── switch("new_tenant")
    │   ├── import_database_schema
    │   │   └── load(db/schema.rb) (padrão)
    │   │   └── OU pg_dump + clone (use_sql = true)
    │   │
    │   └── seed_data (se seed_after_create = true)
    │       └── load(db/seeds.rb)
    │
    └── switch back
```

---

## 10. Resumo e Recomendações

### O que o Apartment faz bem:
- Abstração limpa do conceito de multi-tenancy
- Suporte a múltiplos bancos (PostgreSQL, MySQL, SQLite, JDBC)
- Elevators flexíveis para roteamento automático
- Extensibilidade via callbacks e custom elevators
- Boa cobertura de testes (ratio 2:1)
- Integração transparente com Rake tasks do Rails

### O que precisa de atenção para uso com Rails 8+ / Ruby 3.3+:
1. **Atualizar restrição de `activerecord`** no gemspec
2. **Substituir APIs depreciadas** (`connection_config`, `File.exists?`)
3. **Adaptar para nova API de migrações** do Rails 7+/8+
4. **Avaliar conflito com multi-database nativo** do Rails 6+
5. **Modernizar dependências** de desenvolvimento
6. **Considerar alternativas** como `acts_as_tenant` (row-level) ou `ros-apartment` (fork mantido)
7. **Considerar o fork `apartment-ruby/apartment`** que é mais atualizado que o original `influitive/apartment`

### Status do projeto:
O projeto original está **inativo desde junho de 2019** (6+ anos sem commits). Para uso em produção com Rails 8+, é necessário um **trabalho significativo de modernização** ou a adoção de um fork mantido pela comunidade.
