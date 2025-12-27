# Сравнение подходов к автоматизации установки ПО

[English version below](#comparison-of-software-installation-automation-approaches)

Этот документ сравнивает подход, используемый в репозитории **Install Scripts**, с другими популярными инструментами автоматизации: **Ansible**, **Puppet**, **Chef** и **SaltStack**.

## Содержание

- [Обзор подходов](#обзор-подходов)
- [Сравнительная таблица](#сравнительная-таблица)
- [Подробное сравнение](#подробное-сравнение)
  - [Install Scripts (этот проект)](#install-scripts-этот-проект)
  - [Ansible](#ansible)
  - [Puppet](#puppet)
  - [Chef](#chef)
  - [SaltStack](#saltstack)
- [Рекомендации для разных пользователей](#рекомендации-для-разных-пользователей)
- [Заключение](#заключение)

---

## Обзор подходов

| Инструмент | Тип | Требования к агенту | Язык конфигурации | Сложность освоения |
|------------|-----|---------------------|-------------------|-------------------|
| **Install Scripts** | Bash-скрипты + API + GUI | Нет | Bash | Очень низкая |
| **Ansible** | Push-модель | Нет (agentless) | YAML | Низкая |
| **Puppet** | Pull-модель | Да | Ruby DSL | Высокая |
| **Chef** | Pull-модель | Да | Ruby DSL | Высокая |
| **SaltStack** | Push/Pull | Опционально | YAML/Python | Средняя |

---

## Сравнительная таблица

### Ключевые характеристики

| Характеристика | Install Scripts | Ansible | Puppet | Chef | SaltStack |
|----------------|-----------------|---------|--------|------|-----------|
| **Установка сервера управления** | Не требуется | Не требуется | Требуется | Требуется | Требуется |
| **Установка агента на целевых машинах** | Нет | Нет | Да | Да | Опционально |
| **Идемпотентность** | Да | Да | Да | Да | Да |
| **GUI-интерфейс** | Да (десктоп) | Да (AWX) | Да (Enterprise) | Да (Automate) | Да (Enterprise) |
| **API** | Да (Flask) | Да | Да | Да | Да |
| **Управление секретами** | Переменные окружения | Ansible Vault | Hiera | Encrypted Data Bags | Pillar |
| **Стоимость** | Бесплатно | Бесплатно / Enterprise | Бесплатно / Enterprise | Бесплатно / Enterprise | Бесплатно / Enterprise |

### Плюсы и минусы

#### Install Scripts (этот проект)

| Плюсы | Минусы |
|-------|--------|
| Установка одной командой через curl | Ограничен Ubuntu 24.04 |
| Не требует дополнительных инструментов | Меньше гибкости для сложных сценариев |
| GUI-приложение для Windows/Mac/Linux | Менее масштабируем для 100+ серверов |
| Простой API для интеграции | Нет встроенного управления секретами |
| Понятный bash-код | Меньше сообщество |
| Цветной вывод результатов | Нет оркестрации между серверами |
| Автоматическая настройка SSL | — |

#### Ansible

| Плюсы | Минусы |
|-------|--------|
| Agentless (работает по SSH) | Медленнее на большом количестве узлов |
| Простой YAML-синтаксис | Нет Python API для программирования |
| Огромное сообщество | Ansible AWX не интегрирован с CLI |
| Готовые роли в Ansible Galaxy | Требует Python на целевых машинах |
| Отличная документация | — |
| Поддержка Red Hat | — |

#### Puppet

| Плюсы | Минусы |
|-------|--------|
| Зрелая платформа | Крутая кривая обучения |
| Отличный для compliance | Требует агента на каждом сервере |
| Подробная отчётность | Ruby DSL сложнее YAML |
| Принудительное соответствие состоянию | Дороже для Enterprise |
| Хорошо для больших инфраструктур | Сложнее настройка |

#### Chef

| Плюсы | Минусы |
|-------|--------|
| Мощный Ruby DSL | Высокий порог входа |
| Отличное тестирование (Test Kitchen) | Требует знания Ruby |
| Chef InSpec для compliance | Сложная архитектура |
| Гибкость настройки | Требует агента |
| Хорошо для разработчиков | — |

#### SaltStack

| Плюсы | Минусы |
|-------|--------|
| Очень быстрый | Сложнее первоначальная настройка |
| Масштабируется до 10000+ узлов | Меньше документации |
| Event-driven архитектура | Куплен VMware/Broadcom |
| Поддержка agentless режима | Меньше сообщество чем у Ansible |
| Мощная система реакторов | — |

---

## Подробное сравнение

### Install Scripts (этот проект)

**Подход**: Коллекция самодостаточных bash-скриптов, каждый из которых полностью устанавливает и настраивает конкретное ПО. Дополнительно предоставляются API (Flask) и GUI (PyQt6) для удобства использования.

**Пример использования**:
```bash
# Прямой запуск
curl -fsSL -o- https://raw.githubusercontent.com/andchir/install_scripts/refs/heads/main/scripts/pocketbase.sh | bash -s -- example.com

# Через API
curl -X POST http://localhost:5000/api/install \
  -H "Content-Type: application/json" \
  -d '{"script_name": "pocketbase", "server_ip": "192.168.1.100", "server_root_password": "pass", "additional": "example.com"}'
```

**Когда использовать**:
- Быстрая установка популярного ПО на Ubuntu-серверы
- Когда не хочется изучать сложные инструменты
- Для одиночных серверов или небольших проектов
- Когда нужен GUI для менее технических пользователей

### Ansible

**Подход**: Декларативные playbooks в YAML-формате, выполняемые по SSH без установки агентов.

**Пример использования**:
```yaml
# playbook.yml
- hosts: webservers
  tasks:
    - name: Install nginx
      apt:
        name: nginx
        state: present
    - name: Start nginx
      service:
        name: nginx
        state: started
```

```bash
ansible-playbook -i inventory playbook.yml
```

**Когда использовать**:
- Управление несколькими серверами
- CI/CD pipelines
- Когда команда уже знает YAML
- Для cloud-инфраструктуры

### Puppet

**Подход**: Декларативное описание желаемого состояния системы на Ruby DSL с централизованным сервером.

**Пример использования**:
```puppet
# manifest.pp
package { 'nginx':
  ensure => installed,
}

service { 'nginx':
  ensure => running,
  enable => true,
  require => Package['nginx'],
}
```

**Когда использовать**:
- Большие корпоративные инфраструктуры
- Строгие требования к compliance
- Когда нужна детальная отчётность
- Для поддержания единообразного состояния систем

### Chef

**Подход**: Инфраструктура как код на Ruby с мощными возможностями тестирования.

**Пример использования**:
```ruby
# recipe.rb
package 'nginx' do
  action :install
end

service 'nginx' do
  action [:enable, :start]
end
```

**Когда использовать**:
- Команды с опытом в Ruby
- Сложные сценарии развёртывания
- Когда важно тестирование инфраструктуры
- Для compliance-as-code (Chef InSpec)

### SaltStack

**Подход**: Быстрая event-driven автоматизация с поддержкой как агентного, так и безагентного режима.

**Пример использования**:
```yaml
# state.sls
nginx:
  pkg.installed: []
  service.running:
    - enable: True
    - require:
      - pkg: nginx
```

**Когда использовать**:
- Очень большие инфраструктуры (10000+ узлов)
- Когда нужна реакция на события в реальном времени
- Для динамических облачных окружений

---

## Рекомендации для разных пользователей

### Начинающие пользователи

**Рекомендуется: Install Scripts или Ansible**

- **Install Scripts**: Если нужно быстро установить конкретное ПО на Ubuntu без изучения новых инструментов. Просто скопируйте команду и запустите.
- **Ansible**: Если планируете расти в DevOps и управлять несколькими серверами. YAML легко читается и понимается.

### Системные администраторы

**Рекомендуется: Ansible или SaltStack**

- **Ansible**: Универсальный выбор для большинства задач. Не требует агентов, легко начать.
- **SaltStack**: Если управляете большим количеством серверов и важна скорость.

### DevOps-инженеры

**Рекомендуется: Ansible, Chef или SaltStack**

- **Ansible**: Для cloud-native инфраструктуры и CI/CD.
- **Chef**: Если команда предпочитает Ruby и нужно мощное тестирование.
- **SaltStack**: Для event-driven автоматизации и реакции на инциденты.

### Корпоративные команды

**Рекомендуется: Puppet или Chef**

- **Puppet**: Для строгого compliance и аудита конфигураций.
- **Chef**: Для сложных требований с детальным тестированием.

---

## Заключение

Выбор инструмента зависит от конкретных потребностей:

| Сценарий | Рекомендация |
|----------|--------------|
| Быстрая установка ПО на один сервер | Install Scripts |
| Начать изучать автоматизацию | Ansible |
| Управление 5-100 серверами | Ansible |
| Управление 100-1000 серверами | Ansible или Puppet |
| Управление 1000+ серверами | SaltStack |
| Строгий compliance | Puppet или Chef |
| Команда знает Ruby | Chef |
| Нужен GUI без сложной настройки | Install Scripts |

**Install Scripts** занимает нишу простого и быстрого решения для установки популярного ПО на Ubuntu-серверы, особенно полезного для:
- Одиночных серверов
- Быстрого прототипирования
- Пользователей без DevOps-опыта
- Случаев, когда нужен GUI

Для более сложных сценариев с множеством серверов рекомендуется рассмотреть **Ansible** как следующий шаг.

---

# Comparison of Software Installation Automation Approaches

This document compares the approach used in the **Install Scripts** repository with other popular automation tools: **Ansible**, **Puppet**, **Chef**, and **SaltStack**.

## Table of Contents

- [Approach Overview](#approach-overview)
- [Comparison Table](#comparison-table)
- [Detailed Comparison](#detailed-comparison)
  - [Install Scripts (this project)](#install-scripts-this-project)
  - [Ansible](#ansible-1)
  - [Puppet](#puppet-1)
  - [Chef](#chef-1)
  - [SaltStack](#saltstack-1)
- [Recommendations for Different Users](#recommendations-for-different-users)
- [Conclusion](#conclusion)

---

## Approach Overview

| Tool | Type | Agent Required | Configuration Language | Learning Curve |
|------|------|----------------|------------------------|----------------|
| **Install Scripts** | Bash scripts + API + GUI | No | Bash | Very Low |
| **Ansible** | Push-based | No (agentless) | YAML | Low |
| **Puppet** | Pull-based | Yes | Ruby DSL | High |
| **Chef** | Pull-based | Yes | Ruby DSL | High |
| **SaltStack** | Push/Pull | Optional | YAML/Python | Medium |

---

## Comparison Table

### Key Characteristics

| Feature | Install Scripts | Ansible | Puppet | Chef | SaltStack |
|---------|-----------------|---------|--------|------|-----------|
| **Management server installation** | Not required | Not required | Required | Required | Required |
| **Agent on target machines** | No | No | Yes | Yes | Optional |
| **Idempotency** | Yes | Yes | Yes | Yes | Yes |
| **GUI interface** | Yes (desktop) | Yes (AWX) | Yes (Enterprise) | Yes (Automate) | Yes (Enterprise) |
| **API** | Yes (Flask) | Yes | Yes | Yes | Yes |
| **Secrets management** | Environment variables | Ansible Vault | Hiera | Encrypted Data Bags | Pillar |
| **Cost** | Free | Free / Enterprise | Free / Enterprise | Free / Enterprise | Free / Enterprise |

### Pros and Cons

#### Install Scripts (this project)

| Pros | Cons |
|------|------|
| One-command installation via curl | Limited to Ubuntu 24.04 |
| No additional tools required | Less flexibility for complex scenarios |
| GUI app for Windows/Mac/Linux | Less scalable for 100+ servers |
| Simple API for integration | No built-in secrets management |
| Readable bash code | Smaller community |
| Colored output | No cross-server orchestration |
| Automatic SSL configuration | — |

#### Ansible

| Pros | Cons |
|------|------|
| Agentless (works over SSH) | Slower on large number of nodes |
| Simple YAML syntax | No Python API for programming |
| Huge community | Ansible AWX not integrated with CLI |
| Ready-made roles in Ansible Galaxy | Requires Python on target machines |
| Excellent documentation | — |
| Red Hat support | — |

#### Puppet

| Pros | Cons |
|------|------|
| Mature platform | Steep learning curve |
| Great for compliance | Requires agent on each server |
| Detailed reporting | Ruby DSL more complex than YAML |
| Enforced state compliance | More expensive for Enterprise |
| Good for large infrastructures | More complex setup |

#### Chef

| Pros | Cons |
|------|------|
| Powerful Ruby DSL | High entry barrier |
| Excellent testing (Test Kitchen) | Requires Ruby knowledge |
| Chef InSpec for compliance | Complex architecture |
| Configuration flexibility | Requires agent |
| Good for developers | — |

#### SaltStack

| Pros | Cons |
|------|------|
| Very fast | More complex initial setup |
| Scales to 10000+ nodes | Less documentation |
| Event-driven architecture | Acquired by VMware/Broadcom |
| Supports agentless mode | Smaller community than Ansible |
| Powerful reactor system | — |

---

## Detailed Comparison

### Install Scripts (this project)

**Approach**: A collection of self-contained bash scripts, each fully installing and configuring specific software. Additionally provides API (Flask) and GUI (PyQt6) for convenience.

**Usage example**:
```bash
# Direct execution
curl -fsSL -o- https://raw.githubusercontent.com/andchir/install_scripts/refs/heads/main/scripts/pocketbase.sh | bash -s -- example.com

# Via API
curl -X POST http://localhost:5000/api/install \
  -H "Content-Type: application/json" \
  -d '{"script_name": "pocketbase", "server_ip": "192.168.1.100", "server_root_password": "pass", "additional": "example.com"}'
```

**When to use**:
- Quick installation of popular software on Ubuntu servers
- When you don't want to learn complex tools
- For single servers or small projects
- When you need a GUI for less technical users

### Ansible

**Approach**: Declarative playbooks in YAML format, executed over SSH without installing agents.

**Usage example**:
```yaml
# playbook.yml
- hosts: webservers
  tasks:
    - name: Install nginx
      apt:
        name: nginx
        state: present
    - name: Start nginx
      service:
        name: nginx
        state: started
```

```bash
ansible-playbook -i inventory playbook.yml
```

**When to use**:
- Managing multiple servers
- CI/CD pipelines
- When the team already knows YAML
- For cloud infrastructure

### Puppet

**Approach**: Declarative description of desired system state in Ruby DSL with a centralized server.

**Usage example**:
```puppet
# manifest.pp
package { 'nginx':
  ensure => installed,
}

service { 'nginx':
  ensure => running,
  enable => true,
  require => Package['nginx'],
}
```

**When to use**:
- Large enterprise infrastructures
- Strict compliance requirements
- When detailed reporting is needed
- For maintaining uniform system states

### Chef

**Approach**: Infrastructure as code in Ruby with powerful testing capabilities.

**Usage example**:
```ruby
# recipe.rb
package 'nginx' do
  action :install
end

service 'nginx' do
  action [:enable, :start]
end
```

**When to use**:
- Teams with Ruby experience
- Complex deployment scenarios
- When infrastructure testing is important
- For compliance-as-code (Chef InSpec)

### SaltStack

**Approach**: Fast event-driven automation supporting both agent-based and agentless modes.

**Usage example**:
```yaml
# state.sls
nginx:
  pkg.installed: []
  service.running:
    - enable: True
    - require:
      - pkg: nginx
```

**When to use**:
- Very large infrastructures (10000+ nodes)
- When real-time event reactions are needed
- For dynamic cloud environments

---

## Recommendations for Different Users

### Beginners

**Recommended: Install Scripts or Ansible**

- **Install Scripts**: If you need to quickly install specific software on Ubuntu without learning new tools. Just copy the command and run it.
- **Ansible**: If you plan to grow in DevOps and manage multiple servers. YAML is easy to read and understand.

### System Administrators

**Recommended: Ansible or SaltStack**

- **Ansible**: Universal choice for most tasks. No agents required, easy to start.
- **SaltStack**: If you manage a large number of servers and speed is important.

### DevOps Engineers

**Recommended: Ansible, Chef, or SaltStack**

- **Ansible**: For cloud-native infrastructure and CI/CD.
- **Chef**: If the team prefers Ruby and needs powerful testing.
- **SaltStack**: For event-driven automation and incident response.

### Enterprise Teams

**Recommended: Puppet or Chef**

- **Puppet**: For strict compliance and configuration auditing.
- **Chef**: For complex requirements with detailed testing.

---

## Conclusion

The choice of tool depends on specific needs:

| Scenario | Recommendation |
|----------|----------------|
| Quick software installation on one server | Install Scripts |
| Starting to learn automation | Ansible |
| Managing 5-100 servers | Ansible |
| Managing 100-1000 servers | Ansible or Puppet |
| Managing 1000+ servers | SaltStack |
| Strict compliance | Puppet or Chef |
| Team knows Ruby | Chef |
| Need GUI without complex setup | Install Scripts |

**Install Scripts** fills the niche of a simple and quick solution for installing popular software on Ubuntu servers, especially useful for:
- Single servers
- Rapid prototyping
- Users without DevOps experience
- Cases when a GUI is needed

For more complex scenarios with multiple servers, consider **Ansible** as the next step.

---

## References / Ссылки

- [Chef vs. Puppet vs. Ansible vs. SaltStack - configuration management tools compared](https://www.justaftermidnight247.com/insights/chef-vs-puppet-vs-ansible-vs-saltstack-configuration-management-tools-compared/)
- [Ansible vs Puppet vs Chef vs SaltStack: 2025 Comparison](https://teachmeansible.com/blog/configuration-management-comparison)
- [Understanding Ansible, Terraform, Puppet, Chef, and Salt - Red Hat](https://www.redhat.com/en/topics/automation/understanding-ansible-vs-terraform-puppet-chef-and-salt)
- [Comparing Ansible, Terraform, Chef, Salt, and Puppet for cloud-native apps](https://www.redpanda.com/blog/ansible-terraform-chef-salt-puppet-cloud)
- [Why is Ansible better than shell scripting?](https://timstaley.co.uk/posts/why-ansible/)
- [Shell Scripts vs Ansible for Configuration Management](https://medium.com/@devopskeerti/when-to-use-what-shell-scripts-vs-ansible-for-configuration-management-98e8d4fb6d20)
- [Ansible Alternatives in 2025](https://www.automq.com/blog/ansible-alternatives-2025-terraform-chef-salt-puppet-cfengine)
