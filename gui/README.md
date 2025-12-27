# Install Scripts GUI

Графический интерфейс для установки программного обеспечения на удалённые серверы Ubuntu.

## Описание

Приложение предоставляет те же возможности, что и API, но без использования базы данных и блокировщика. Позволяет:
- Подключаться к удалённому серверу по SSH
- Выбирать программное обеспечение для установки из списка
- Указывать дополнительные параметры (например, доменное имя)
- Отслеживать процесс установки в реальном времени

## Требования

- Python 3.9+
- PyQt6 6.4.0+
- paramiko 3.0.0+

## Установка

### Ubuntu / Debian

```bash
# Установка системных зависимостей
sudo apt-get update
sudo apt-get install -y python3 python3-pip python3-venv

# Создание виртуального окружения
cd gui
python3 -m venv venv
source venv/bin/activate

# Установка зависимостей Python
pip install -r requirements.txt
```

### Windows

1. Скачайте и установите Python 3.9+ с [python.org](https://www.python.org/downloads/)
2. Откройте командную строку (cmd) или PowerShell:

```powershell
# Переход в директорию gui
cd gui

# Создание виртуального окружения
python -m venv venv

# Активация виртуального окружения
venv\Scripts\activate

# Установка зависимостей
pip install -r requirements.txt
```

### macOS

```bash
# Установка Python через Homebrew (если не установлен)
brew install python3

# Создание виртуального окружения
cd gui
python3 -m venv venv
source venv/bin/activate

# Установка зависимостей
pip install -r requirements.txt
```

## Запуск

```bash
# Активируйте виртуальное окружение (если ещё не активировано)
# Linux/macOS:
source venv/bin/activate
# Windows:
# venv\Scripts\activate

# Запуск приложения (русский интерфейс)
python main.py

# Запуск с английским интерфейсом
python main.py --lang en
```

## Использование

1. Введите IP адрес сервера
2. Введите root пароль для SSH
3. Укажите дополнительную информацию (например, доменное имя), если требуется
4. Выберите программное обеспечение для установки из списка
5. Нажмите кнопку "Установить"
6. Отслеживайте процесс установки в области отчёта

## Сборка исполняемого файла

### PyInstaller (все платформы)

```bash
# Установка PyInstaller
pip install pyinstaller

# Сборка с использованием spec-файла (рекомендуется)
# Spec-файл автоматически включает файлы данных (data_ru.json, data_en.json)
cd gui
pyinstaller InstallScripts.spec
```

Исполняемый файл будет создан в директории `dist/`.

> **Важно:** Используйте spec-файл `InstallScripts.spec` для сборки. Он автоматически
> включает необходимые файлы данных (`data_ru.json`, `data_en.json`) в исполняемый файл.
> Без этих файлов список скриптов не будет отображаться.

### Windows (дополнительно)

```powershell
# Сборка на Windows с использованием spec-файла
cd gui
pyinstaller InstallScripts.spec
```

Для создания установщика можно использовать [Inno Setup](https://jrsoftware.org/isinfo.php) или [NSIS](https://nsis.sourceforge.io/).

### macOS (создание .app)

```bash
# Сборка .app с использованием spec-файла
cd gui
pyinstaller InstallScripts.spec
```

Для создания DMG-образа можно использовать:
```bash
# Установка create-dmg
brew install create-dmg

# Создание DMG
create-dmg \
    --volname "Install Scripts" \
    --window-pos 200 120 \
    --window-size 600 400 \
    --icon-size 100 \
    --app-drop-link 450 185 \
    "InstallScripts.dmg" \
    "dist/"
```

### Linux (создание AppImage)

```bash
# Установка appimagetool
wget https://github.com/AppImage/AppImageKit/releases/download/continuous/appimagetool-x86_64.AppImage
chmod +x appimagetool-x86_64.AppImage

# Сборка с PyInstaller
pyinstaller --onedir --windowed --name "InstallScripts" main.py

# Создание структуры AppImage
mkdir -p InstallScripts.AppDir/usr/bin
cp -r dist/InstallScripts/* InstallScripts.AppDir/usr/bin/

# Создание desktop file
cat > InstallScripts.AppDir/InstallScripts.desktop << EOF
[Desktop Entry]
Type=Application
Name=Install Scripts
Exec=InstallScripts
Icon=installscripts
Categories=Utility;
EOF

# Создание AppRun
cat > InstallScripts.AppDir/AppRun << EOF
#!/bin/bash
SELF=\$(readlink -f "\$0")
HERE=\${SELF%/*}
exec "\${HERE}/usr/bin/InstallScripts" "\$@"
EOF
chmod +x InstallScripts.AppDir/AppRun

# Создание AppImage
./appimagetool-x86_64.AppImage InstallScripts.AppDir
```

## Параметры командной строки

| Параметр | Описание | По умолчанию |
|----------|----------|--------------|
| `--lang` | Язык интерфейса (`ru` или `en`) | `en` |
| `--debug` | Включить отладочное логирование | Выключено |

## Отладка

Если список скриптов не загружается (особенно после сборки исполняемого файла), включите режим отладки:

```bash
# Через параметр командной строки
python main.py --debug

# Или через переменную окружения
INSTALL_SCRIPTS_DEBUG=1 python main.py

# На Windows (PowerShell)
$env:INSTALL_SCRIPTS_DEBUG="1"; python main.py
```

В режиме отладки создаётся лог-файл `install_scripts_debug.log` в домашней директории пользователя (для исполняемого файла) или в текущей директории (для Python-скрипта).

## Структура проекта

```
gui/
├── main.py              # Основной файл приложения
├── InstallScripts.spec  # PyInstaller spec-файл для сборки
├── requirements.txt     # Зависимости Python
└── README.md            # Документация
```

## Лицензия

MIT
