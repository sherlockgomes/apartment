# Uso Consiso — Apartment Gem com tenant `agros-api`

## Pré-requisitos

- Rails 7+ com PostgreSQL
- Gem Apartment instalada e configurada
- `config/initializers/apartment.rb` com `excluded_models` e `tenant_names` definidos

---

## 1. Configuração mínima (`config/initializers/apartment.rb`)

```ruby
Apartment.configure do |config|
  config.excluded_models = %w[Company User]  # Models que ficam no schema public
  config.use_schemas = true                 # PostgreSQL schemas (padrão)
  config.tenant_names = -> { ['agros-api'] } # ou lambda { Company.pluck(:database) }
end
```

---

## 2. Console Rails — Teste rápido

```bash
rails console
```

```ruby
# Criar o tenant agros-api (schema PostgreSQL)
Apartment::Tenant.create('agros-api')

# Migrar o tenant
Apartment::Tenant.switch('agros-api') { Apartment::Migrator.migrate('agros-api') }

# Verificar tenant atual
Apartment::Tenant.current
# => "agros-api"

# Executar código no contexto do tenant
Apartment::Tenant.switch('agros-api') do
  User.count
  # ou qualquer operação ActiveRecord
end

# Resetar para o schema padrão
Apartment::Tenant.reset
Apartment::Tenant.current
# => "public" ou default_schema
```

---

## 3. Teste em um bloco

```ruby
Apartment::Tenant.switch('agros-api') do
  puts "Tenant atual: #{Apartment::Tenant.current}"
  # Criar registros, consultas, etc.
end
# Retorna automaticamente ao tenant anterior
```

---

## 4. Comandos Rake

```bash
# Migrar todos os tenants configurados
rake apartment:migrate

# Seed nos tenants
rake apartment:seed
```

---

## 5. Elevator (HTTP Request)

Com subdomínio `agros-api.seudominio.com`, o Elevator Subdomain detecta o tenant automaticamente:

```ruby
# config/initializers/apartment.rb
require 'apartment/elevators/subdomain'
Rails.application.config.middleware.use Apartment::Elevators::Subdomain
```

---

## Checklist de teste

| Ação                    | Comando / Código                                           |
|-------------------------|------------------------------------------------------------|
| Criar tenant            | `Apartment::Tenant.create('agros-api')`                    |
| Migrar tenant           | `Apartment::Tenant.switch('agros-api') { Apartment::Migrator.migrate('agros-api') }` |
| Tenant atual            | `Apartment::Tenant.current`                                |
| Executar no tenant      | `Apartment::Tenant.switch('agros-api') { ... }`            |
| Dropar tenant (cuidado) | `Apartment::Tenant.drop('agros-api')`                      |
