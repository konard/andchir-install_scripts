# Install Scripts

Коллекция скриптов для автоматической установки различного программного обеспечения на удалённые серверы Ubuntu 24.04.

## Описание проекта

Этот проект предоставляет набор bash-скриптов для быстрого развёртывания популярного программного обеспечения на серверах Ubuntu. Все скрипты:

- Адаптированы под Ubuntu 24.04
- Поддерживают идемпотентность (можно запускать повторно)
- Автоматически создают необходимых пользователей
- Настраивают nginx с SSL-сертификатами (Let's Encrypt)
- Выводят результаты установки с цветовой подсветкой

## Доступные скрипты

| Скрипт | Описание |
|--------|----------|
| `install-scripts-api-flask.sh` | API для установки ПО на удалённый сервер Ubuntu |
| `various-useful-api-django.sh` | Набор полезных API с использованием Django |
| `openchatroulette.sh` | Видео чат-рулетка |
| `pocketbase.sh` | Бэкенд на Go с встроенной базой данных SQLite, аутентификацией, хранилищем файлов и админ-панелью |
| `mysql-phpmyadmin.sh` | Сервер базы данных MySQL с веб-интерфейсом phpMyAdmin |

## Использование

### Запуск скрипта напрямую

```bash
curl -fsSL -o- https://raw.githubusercontent.com/andchir/install_scripts/refs/heads/main/scripts/<script_name>.sh | bash -s -- <domain_name>
```

Пример:
```bash
curl -fsSL -o- https://raw.githubusercontent.com/andchir/install_scripts/refs/heads/main/scripts/pocketbase.sh | bash -s -- example.com
```

### Использование через API

Проект включает Flask API для управления скриптами и удалённой установки ПО.

## API

### Запуск API сервера

```bash
cd api
pip install flask paramiko
python app.py --port 5000 --host 0.0.0.0
```

### Переменные окружения

Можно задать переменные окружения в файле `.env` в директории `api/`. Пример файла: `api/.env.example`.

| Переменная | Описание | По умолчанию |
|------------|----------|--------------|
| `API_KEY` | API ключ для аутентификации (если не задан, аутентификация отключена) | - |
| `SCRIPTS_DIR` | Директория со скриптами | `../scripts` |
| `DATA_DIR` | Директория с файлами данных | `..` |
| `SCRIPTS_BASE_URL` | Базовый URL для скачивания скриптов | `https://raw.githubusercontent.com/andchir/install_scripts/refs/heads/main/scripts` |

### Аутентификация API

Если переменная окружения `API_KEY` задана, эндпоинт `/api/install` требует API ключ для доступа.

API ключ можно передать:
- В заголовке `X-API-Key`
- В параметре запроса `api_key`

**Генерация безопасного ключа:**
```bash
python -c "import secrets; print(secrets.token_urlsafe(32))"
```

### Эндпоинты API

#### `GET /`

Информация об API и список доступных эндпоинтов.

**Ответ:**
```json
{
  "name": "Install Scripts API",
  "version": "1.0.0",
  "endpoints": {
    "/": "API information (this page)",
    "/health": "Health check endpoint",
    "/api/scripts_list": "List all available installation scripts (supports ?lang=ru|en)",
    "/api/script/<script_name>": "Get information about a single script by script_name (supports ?lang=ru|en)",
    "/api/install": "Execute an installation script on a remote server via SSH (POST: script_name, server_ip, server_root_password, additional)"
  }
}
```

#### `GET /health`

Проверка состояния API.

**Ответ:**
```json
{
  "status": "healthy",
  "message": "API is running"
}
```

#### `GET /api/scripts_list`

Получение списка всех доступных скриптов.

**Параметры запроса:**
| Параметр | Тип | Описание | По умолчанию |
|----------|-----|----------|--------------|
| `lang` | string | Язык данных (`ru` или `en`) | `ru` |

**Пример запроса:**
```bash
curl http://localhost:5000/api/scripts_list?lang=ru
```

**Ответ:**
```json
{
  "success": true,
  "count": 4,
  "scripts": [
    {
      "name": "andchir/install_scripts",
      "script_name": "install-scripts-api-flask",
      "description": "API для установки ПО на удалённый сервер Ubuntu",
      "info": "Необходимый параметр: доменное имя"
    }
  ]
}
```

#### `GET /api/script/<script_name>`

Получение информации о конкретном скрипте.

**Параметры URL:**
| Параметр | Тип | Описание |
|----------|-----|----------|
| `script_name` | string | Имя скрипта (без расширения `.sh`) |

**Параметры запроса:**
| Параметр | Тип | Описание | По умолчанию |
|----------|-----|----------|--------------|
| `lang` | string | Язык данных (`ru` или `en`) | `ru` |

**Пример запроса:**
```bash
curl http://localhost:5000/api/script/pocketbase?lang=ru
```

**Ответ:**
```json
{
  "success": true,
  "result": {
    "name": "pocketbase/pocketbase",
    "script_name": "pocketbase",
    "description": "Бэкенд на Go с встроенной базой данных SQLite, аутентификацией, хранилищем файлов и админ-панелью",
    "info": "Необходимый параметр: доменное имя"
  }
}
```

#### `POST /api/install`

Запуск установки ПО на удалённом сервере через SSH.

**Требует API ключ для аутентификации**, если переменная `API_KEY` задана.

**Заголовки:**
```
Content-Type: application/json
X-API-Key: your_api_key (если API_KEY задан)
```

**Тело запроса:**
| Поле | Тип | Обязательное | Описание |
|------|-----|--------------|----------|
| `script_name` | string | Да | Имя скрипта для выполнения |
| `server_ip` | string | Да | IP-адрес удалённого сервера |
| `server_root_password` | string | Да | Пароль root для SSH |
| `additional` | string | Нет | Дополнительные параметры для скрипта (например, доменное имя) |

**Пример запроса (с API ключом):**
```bash
curl -X POST http://localhost:5000/api/install \
  -H "Content-Type: application/json" \
  -H "X-API-Key: your_api_key" \
  -d '{
    "script_name": "pocketbase",
    "server_ip": "192.168.1.100",
    "server_root_password": "your_password",
    "additional": "example.com"
  }'
```

**Успешный ответ:**
```json
{
  "success": true,
  "output": "...",
  "error": null
}
```

**Ответ с ошибкой:**
```json
{
  "success": false,
  "output": "...",
  "error": "SSH authentication failed. Please check the password."
}
```

### Коды ответов

| Код | Описание |
|-----|----------|
| 200 | Успешный запрос |
| 400 | Неверный запрос (отсутствуют обязательные поля) |
| 401 | Требуется аутентификация (отсутствует или неверный API ключ) |
| 403 | Доступ запрещён |
| 404 | Ресурс не найден |
| 500 | Внутренняя ошибка сервера |
| 503 | Сервис недоступен (не установлена библиотека paramiko) |

## Требования к скриптам

Подробные требования к скриптам описаны в файле [requirements_for_scripts_ru.md](requirements_for_scripts_ru.md).

## Лицензия

MIT
