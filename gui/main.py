#!/usr/bin/env python3
"""
Install Scripts GUI Application

A PyQt6-based graphical interface for installing software on remote Ubuntu servers.
This application provides the same functionality as the API but without database
and rate limiting features.

Usage:
    python main.py [--lang LANG]

Arguments:
    --lang LANG  Language code ('ru' or 'en', default: 'ru')
"""

import sys
import os
import re
import json
import argparse
import logging
from typing import Optional, List, Dict, Any

from PyQt6.QtWidgets import (
    QApplication, QMainWindow, QWidget, QVBoxLayout, QHBoxLayout,
    QLabel, QLineEdit, QPushButton, QTextEdit, QComboBox,
    QGroupBox, QMessageBox, QSplitter, QFrame, QSpacerItem, QSizePolicy
)
from PyQt6.QtCore import Qt, QThread, pyqtSignal, QTimer
from PyQt6.QtGui import QFont, QIcon, QTextCursor

# SSH imports
try:
    import paramiko
    SSH_AVAILABLE = True
except ImportError:
    SSH_AVAILABLE = False
    paramiko = None


# Configure logging
# Enable debug logging via environment variable: INSTALL_SCRIPTS_DEBUG=1
# or via command line: --debug
logger = logging.getLogger(__name__)

# Configuration
SCRIPTS_BASE_URL = 'https://raw.githubusercontent.com/andchir/install_scripts/refs/heads/main/scripts'
SSH_DEFAULT_PORT = 22
SSH_DEFAULT_TIMEOUT = 30
DEFAULT_LANG = 'en'

# Translations
TRANSLATIONS = {
    'ru': {
        'window_title': 'Install Scripts - Установка ПО',
        'language_label': 'Язык:',
        'server_ip': 'IP адрес сервера:',
        'server_password': 'SSH root пароль сервера:',
        'additional_info': 'Дополнительная информация (например, домен):',
        'software_list': 'Софт для установки на сервере:',
        'install_button': 'Установить',
        'stop_button': 'Остановить',
        'report_title': 'Отчёт',
        'error_no_ip': 'Пожалуйста, введите IP адрес сервера',
        'error_no_password': 'Пожалуйста, введите пароль',
        'error_no_script': 'Пожалуйста, выберите скрипт для установки',
        'error_invalid_ip': 'Неверный формат IP адреса',
        'error_ssh_not_available': 'Библиотека SSH (paramiko) не установлена.\nУстановите её командой: pip install paramiko',
        'status_connecting': 'Подключение к {ip}:{port} через SSH...',
        'status_executing': 'Выполнение скрипта: {script_name}',
        'status_completed': 'Установка завершена успешно',
        'status_error': 'Ошибка: {error}',
        'status_stopped': 'Установка прервана пользователем',
        'clear_button': 'Очистить',
        'error_no_scripts': 'Ошибка: Не удалось загрузить список скриптов.\n\n'
                           'Если вы собрали исполняемый файл, убедитесь что:\n'
                           '1. Вы использовали "pyinstaller InstallScripts.spec" для сборки\n'
                           '2. Файлы данных (data_ru.json, data_en.json) были включены\n\n'
                           'Для отладки запустите с флагом --debug или установите INSTALL_SCRIPTS_DEBUG=1',
    },
    'en': {
        'window_title': 'Install Scripts - Software Installation',
        'language_label': 'Language:',
        'server_ip': 'Server IP address:',
        'server_password': 'SSH root password:',
        'additional_info': 'Additional information (e.g., domain):',
        'software_list': 'Software to install on server:',
        'install_button': 'Install',
        'stop_button': 'Stop',
        'report_title': 'Report',
        'error_no_ip': 'Please enter the server IP address',
        'error_no_password': 'Please enter the password',
        'error_no_script': 'Please select a script to install',
        'error_invalid_ip': 'Invalid IP address format',
        'error_ssh_not_available': 'SSH library (paramiko) is not installed.\nInstall it with: pip install paramiko',
        'status_connecting': 'Connecting to {ip}:{port} via SSH...',
        'status_executing': 'Executing script: {script_name}',
        'status_completed': 'Installation completed successfully',
        'status_error': 'Error: {error}',
        'status_stopped': 'Installation stopped by user',
        'clear_button': 'Clear',
        'error_no_scripts': 'Error: Script list could not be loaded.\n\n'
                           'If you built this as an executable, please ensure:\n'
                           '1. You used "pyinstaller InstallScripts.spec" to build\n'
                           '2. The data files (data_ru.json, data_en.json) were included\n\n'
                           'For debugging, run with --debug flag or set INSTALL_SCRIPTS_DEBUG=1',
    }
}


def strip_ansi_codes(text: Optional[str]) -> Optional[str]:
    """Remove ANSI escape codes from text."""
    if text is None:
        return None
    ansi_escape = re.compile(r'\x1B(?:[@-Z\\-_]|\[[0-?]*[ -/]*[@-~])')
    return ansi_escape.sub('', text)


def get_base_path() -> str:
    """
    Get the base path for resource files.

    Handles both development mode and PyInstaller frozen executable mode.
    In frozen mode, PyInstaller extracts files to a temporary directory
    accessible via sys._MEIPASS.
    """
    if getattr(sys, 'frozen', False) and hasattr(sys, '_MEIPASS'):
        # Running as a PyInstaller bundle
        base_path = sys._MEIPASS
        logger.debug(f"Running as frozen executable, _MEIPASS={base_path}")
    else:
        # Running in normal Python environment
        script_dir = os.path.dirname(os.path.abspath(__file__))
        base_path = os.path.dirname(script_dir)
        logger.debug(f"Running in development mode, base_path={base_path}")

    return base_path


def get_data_file_path(lang: str) -> str:
    """Get the path to the data file for the specified language."""
    base_path = get_base_path()

    data_file = os.path.join(base_path, f'data_{lang}.json')
    logger.debug(f"Looking for data file: {data_file}")

    if os.path.exists(data_file):
        logger.debug(f"Found data file: {data_file}")
        return data_file

    logger.debug(f"Data file not found: {data_file}")

    # Fall back to default language
    default_file = os.path.join(base_path, f'data_{DEFAULT_LANG}.json')
    logger.debug(f"Trying fallback data file: {default_file}")

    if os.path.exists(default_file):
        logger.debug(f"Found fallback data file: {default_file}")
        return default_file

    logger.warning(f"No data file found for language '{lang}' or default '{DEFAULT_LANG}'")

    # List directory contents for debugging
    if os.path.exists(base_path):
        try:
            contents = os.listdir(base_path)
            logger.debug(f"Contents of {base_path}: {contents}")
        except Exception as e:
            logger.debug(f"Could not list directory contents: {e}")

    return ''


def load_scripts(lang: str) -> List[Dict[str, Any]]:
    """Load scripts list from the data file."""
    logger.debug(f"Loading scripts for language: {lang}")

    data_file = get_data_file_path(lang)
    if not data_file:
        logger.warning(f"No data file path returned for language: {lang}")
        return []

    if not os.path.exists(data_file):
        logger.warning(f"Data file does not exist: {data_file}")
        return []

    try:
        logger.debug(f"Opening data file: {data_file}")
        with open(data_file, 'r', encoding='utf-8') as f:
            content = f.read()
            logger.debug(f"Read {len(content)} bytes from {data_file}")
            scripts = json.loads(content)
            logger.info(f"Loaded {len(scripts)} scripts from {data_file}")
            return scripts
    except json.JSONDecodeError as e:
        logger.error(f"JSON parsing error in {data_file}: {e}")
        return []
    except IOError as e:
        logger.error(f"IO error reading {data_file}: {e}")
        return []
    except Exception as e:
        logger.error(f"Unexpected error loading scripts from {data_file}: {e}")
        return []


class SSHWorker(QThread):
    """Worker thread for SSH operations."""

    output_received = pyqtSignal(str)
    status_changed = pyqtSignal(str)
    finished_signal = pyqtSignal(bool, str)

    def __init__(self, server_ip: str, password: str, script_name: str,
                 additional: str = '', port: int = SSH_DEFAULT_PORT):
        super().__init__()
        self.server_ip = server_ip
        self.password = password
        self.script_name = script_name
        self.additional = additional
        self.port = port
        self._stop_requested = False
        self._ssh_client = None

    def request_stop(self):
        """Request the worker to stop."""
        self._stop_requested = True
        if self._ssh_client:
            try:
                self._ssh_client.close()
            except Exception:
                pass

    def run(self):
        """Execute the installation script via SSH."""
        if not SSH_AVAILABLE:
            self.finished_signal.emit(False, 'SSH library (paramiko) is not installed')
            return

        try:
            # Create SSH client
            self._ssh_client = paramiko.SSHClient()
            self._ssh_client.set_missing_host_key_policy(paramiko.AutoAddPolicy())

            self.status_changed.emit(f"Connecting to {self.server_ip}:{self.port}...")
            self.output_received.emit(f"Connecting to {self.server_ip}:{self.port} via SSH...\n")

            # Connect to the server
            self._ssh_client.connect(
                hostname=self.server_ip,
                port=self.port,
                username='root',
                password=self.password,
                timeout=SSH_DEFAULT_TIMEOUT,
                look_for_keys=False,
                allow_agent=False
            )

            if self._stop_requested:
                self.finished_signal.emit(False, 'Stopped by user')
                return

            # Build the command
            script_url = f"{SCRIPTS_BASE_URL}/{self.script_name}.sh"

            if self.additional:
                escaped_additional = self.additional.replace("'", "'\"'\"'")
                command = f"curl -fsSL -o- {script_url} | bash -s -- '{escaped_additional}'"
            else:
                command = f"curl -fsSL -o- {script_url} | bash"

            self.output_received.emit(f"Executing script: {self.script_name}\n")
            self.output_received.emit("-" * 50 + "\n")

            # Execute the command
            stdin, stdout, stderr = self._ssh_client.exec_command(command, get_pty=True)

            # Stream output
            while True:
                if self._stop_requested:
                    self.finished_signal.emit(False, 'Stopped by user')
                    return

                line = stdout.readline()
                if not line:
                    break

                decoded_line = line if isinstance(line, str) else line.decode('utf-8', errors='replace')
                clean_line = strip_ansi_codes(decoded_line)
                self.output_received.emit(clean_line)

            # Read any remaining stderr
            error_output = stderr.read().decode('utf-8', errors='replace')
            if error_output:
                clean_error = strip_ansi_codes(error_output)
                self.output_received.emit(f"\n{clean_error}")

            # Get exit status
            exit_status = stdout.channel.recv_exit_status()

            if exit_status != 0:
                self.finished_signal.emit(False, f'Script exited with status {exit_status}')
            else:
                self.finished_signal.emit(True, 'Installation completed successfully')

        except paramiko.AuthenticationException:
            self.finished_signal.emit(False, 'SSH authentication failed. Please check the password.')
        except paramiko.SSHException as e:
            self.finished_signal.emit(False, f'SSH connection error: {str(e)}')
        except TimeoutError:
            self.finished_signal.emit(False, f'Connection to {self.server_ip} timed out')
        except Exception as e:
            self.finished_signal.emit(False, f'Unexpected error: {str(e)}')
        finally:
            if self._ssh_client:
                try:
                    self._ssh_client.close()
                except Exception:
                    pass


class MainWindow(QMainWindow):
    """Main application window."""

    def __init__(self, lang: str = DEFAULT_LANG):
        super().__init__()
        self.lang = lang
        self.tr = TRANSLATIONS.get(lang, TRANSLATIONS[DEFAULT_LANG])
        self.scripts = load_scripts(lang)
        self.worker = None
        self._scripts_load_error = len(self.scripts) == 0

        logger.debug(f"MainWindow initialized with {len(self.scripts)} scripts")

        self.init_ui()

    def init_ui(self):
        """Initialize the user interface."""
        self.setWindowTitle(self.tr['window_title'])
        self.setMinimumSize(800, 600)

        # Central widget
        central_widget = QWidget()
        self.setCentralWidget(central_widget)

        # Main layout with consistent margins
        main_layout = QVBoxLayout(central_widget)
        main_layout.setContentsMargins(10, 10, 10, 10)
        main_layout.setSpacing(10)

        # Language selector at the top right
        lang_layout = QHBoxLayout()
        lang_layout.addStretch()
        self.lang_label = QLabel(self.tr['language_label'])
        self.lang_combo = QComboBox()
        self.lang_combo.addItem('English', 'en')
        self.lang_combo.addItem('Русский', 'ru')
        # Set current language
        current_index = 0 if self.lang == 'en' else 1
        self.lang_combo.setCurrentIndex(current_index)
        self.lang_combo.currentIndexChanged.connect(self.on_language_changed)
        lang_layout.addWidget(self.lang_label)
        lang_layout.addWidget(self.lang_combo)
        main_layout.addLayout(lang_layout)

        splitter = QSplitter(Qt.Orientation.Vertical)
        main_layout.addWidget(splitter)

        # Top section - Two-column layout: Input fields (left) and software selection (right)
        top_widget = QWidget()
        top_layout = QVBoxLayout(top_widget)
        top_layout.setContentsMargins(0, 0, 0, 0)
        top_layout.setSpacing(10)

        # Horizontal splitter for two-column layout
        columns_splitter = QSplitter(Qt.Orientation.Horizontal)

        # Left column - Input fields frame (IP, password, additional info)
        inputs_frame = QFrame()
        inputs_frame.setFrameShape(QFrame.Shape.StyledPanel)
        inputs_frame.setStyleSheet("""
            QFrame {
                border: 1px solid #ddd;
                border-radius: 4px;
                background-color: white;
            }
            QLabel {
                border: none;
                background-color: transparent;
            }
            QLineEdit {
                border: 1px solid #ccc;
                border-radius: 3px;
                padding: 5px;
            }
        """)
        inputs_layout = QVBoxLayout(inputs_frame)
        inputs_layout.setContentsMargins(10, 10, 10, 10)
        inputs_layout.setSpacing(8)

        # Server IP - vertical layout (label on top of input)
        self.ip_label = QLabel(self.tr['server_ip'])
        inputs_layout.addWidget(self.ip_label)
        self.ip_input = QLineEdit()
        self.ip_input.setPlaceholderText("192.168.1.100")
        inputs_layout.addWidget(self.ip_input)

        # Server Password - vertical layout (label on top of input)
        self.password_label = QLabel(self.tr['server_password'])
        inputs_layout.addWidget(self.password_label)
        self.password_input = QLineEdit()
        self.password_input.setEchoMode(QLineEdit.EchoMode.Password)
        inputs_layout.addWidget(self.password_input)

        # Additional info - vertical layout (label on top of input)
        self.additional_label = QLabel(self.tr['additional_info'])
        inputs_layout.addWidget(self.additional_label)
        self.additional_input = QLineEdit()
        self.additional_input.setPlaceholderText("example.com")
        inputs_layout.addWidget(self.additional_input)

        # Add spacer to push content to top
        inputs_layout.addStretch()

        columns_splitter.addWidget(inputs_frame)

        # Right column - Software selection frame
        software_frame = QFrame()
        software_frame.setFrameShape(QFrame.Shape.StyledPanel)
        software_frame.setStyleSheet("""
            QFrame {
                border: 1px solid #ddd;
                border-radius: 4px;
                background-color: white;
            }
            QLabel {
                border: none;
                background-color: transparent;
            }
            QComboBox {
                border: 1px solid #ccc;
                border-radius: 3px;
                padding: 5px;
            }
        """)
        software_inner_layout = QVBoxLayout(software_frame)
        software_inner_layout.setContentsMargins(10, 10, 10, 10)
        software_inner_layout.setSpacing(8)

        # Software label
        self.software_label = QLabel(self.tr['software_list'])
        self.software_label.setStyleSheet("font-weight: bold; border: none; background-color: transparent;")
        software_inner_layout.addWidget(self.software_label)

        # Dropdown (ComboBox) for script selection
        self.software_combo = QComboBox()
        self.software_combo.setMinimumHeight(30)

        # Populate software dropdown
        for script in self.scripts:
            display_text = script.get('name', '')
            self.software_combo.addItem(display_text, script)

        software_inner_layout.addWidget(self.software_combo)

        # Description text area that updates when selection changes
        self.description_label = QTextEdit()
        self.description_label.setReadOnly(True)
        self.description_label.setMinimumHeight(70)
        self.description_label.setStyleSheet(
            "QTextEdit { background-color: #f5f5f5; padding: 5px; border: 1px solid #ddd; border-radius: 4px; }"
        )
        self.description_label.setVerticalScrollBarPolicy(Qt.ScrollBarPolicy.ScrollBarAsNeeded)
        self.description_label.setHorizontalScrollBarPolicy(Qt.ScrollBarPolicy.ScrollBarAlwaysOff)
        software_inner_layout.addWidget(self.description_label)

        # Connect selection change signal
        self.software_combo.currentIndexChanged.connect(self.on_script_selection_changed)

        # Select first item by default and update description
        if self.scripts:
            self.software_combo.setCurrentIndex(0)
            self.on_script_selection_changed(0)
        else:
            # Show error message if no scripts were loaded
            logger.warning("No scripts available to display in combo box")
            self.description_label.setPlainText(self.tr.get('error_no_scripts', ''))

        columns_splitter.addWidget(software_frame)

        # Set equal column widths
        columns_splitter.setSizes([400, 400])

        top_layout.addWidget(columns_splitter)

        # Buttons - outside the framed sections
        button_layout = QHBoxLayout()
        button_layout.setContentsMargins(0, 0, 0, 0)

        self.install_button = QPushButton(self.tr['install_button'])
        self.install_button.setMinimumHeight(40)
        self.install_button.clicked.connect(self.on_install_clicked)

        self.stop_button = QPushButton(self.tr['stop_button'])
        self.stop_button.setMinimumHeight(40)
        self.stop_button.setEnabled(False)
        self.stop_button.clicked.connect(self.on_stop_clicked)

        button_layout.addWidget(self.install_button)
        button_layout.addWidget(self.stop_button)
        top_layout.addLayout(button_layout)

        splitter.addWidget(top_widget)

        # Bottom section - Report
        bottom_widget = QWidget()
        bottom_layout = QVBoxLayout(bottom_widget)
        bottom_layout.setContentsMargins(0, 0, 0, 0)
        bottom_layout.setSpacing(10)

        # Report frame
        report_frame = QFrame()
        report_frame.setFrameShape(QFrame.Shape.StyledPanel)
        report_frame.setStyleSheet("""
            QFrame {
                border: 1px solid #ddd;
                border-radius: 4px;
                background-color: white;
            }
            QLabel {
                border: none;
                background-color: transparent;
            }
        """)
        report_inner_layout = QVBoxLayout(report_frame)
        report_inner_layout.setContentsMargins(10, 10, 10, 10)
        report_inner_layout.setSpacing(8)

        # Report label
        self.report_label = QLabel(self.tr['report_title'])
        self.report_label.setStyleSheet("font-weight: bold; border: none; background-color: transparent;")
        report_inner_layout.addWidget(self.report_label)

        self.report_text = QTextEdit()
        self.report_text.setReadOnly(True)
        self.report_text.setFont(QFont("Courier New", 10))
        # Set minimum height for 20 lines (approximately 20 * 18 pixels per line)
        self.report_text.setMinimumHeight(200)
        self.report_text.setStyleSheet("border: 1px solid #ccc; border-radius: 3px;")
        report_inner_layout.addWidget(self.report_text)

        bottom_layout.addWidget(report_frame)

        # Clear button - outside the report frame
        self.clear_button = QPushButton(self.tr['clear_button'])
        self.clear_button.clicked.connect(self.clear_report)
        bottom_layout.addWidget(self.clear_button)

        splitter.addWidget(bottom_widget)

        # Set initial splitter sizes (smaller input section, larger report section)
        splitter.setSizes([350, 300])

        # Check SSH availability
        if not SSH_AVAILABLE:
            self.install_button.setEnabled(False)
            self.report_text.setText(self.tr['error_ssh_not_available'])

    def validate_ip(self, ip: str) -> bool:
        """Validate IPv4 address format."""
        pattern = re.compile(r'^(\d{1,3}\.){3}\d{1,3}$')
        if not pattern.match(ip):
            return False
        # Check each octet is 0-255
        octets = ip.split('.')
        return all(0 <= int(octet) <= 255 for octet in octets)

    def on_script_selection_changed(self, index: int):
        """Handle script selection change in dropdown."""
        if index < 0 or index >= len(self.scripts):
            self.description_label.setPlainText("")
            return

        script = self.software_combo.itemData(index)
        if script:
            description = script.get('description', '')
            info = script.get('info', '')
            # Format: description on first line, info on second line (if present)
            if info:
                self.description_label.setPlainText(f"{description}\n\n{info}")
            else:
                self.description_label.setPlainText(description)

    def on_install_clicked(self):
        """Handle install button click."""
        # Validate inputs
        server_ip = self.ip_input.text().strip()
        if not server_ip:
            QMessageBox.warning(self, "Error", self.tr['error_no_ip'])
            return

        if not self.validate_ip(server_ip):
            QMessageBox.warning(self, "Error", self.tr['error_invalid_ip'])
            return

        password = self.password_input.text()
        if not password:
            QMessageBox.warning(self, "Error", self.tr['error_no_password'])
            return

        # Get selected script from combo box
        current_index = self.software_combo.currentIndex()
        if current_index < 0:
            QMessageBox.warning(self, "Error", self.tr['error_no_script'])
            return

        script = self.software_combo.itemData(current_index)
        if not script:
            QMessageBox.warning(self, "Error", self.tr['error_no_script'])
            return

        script_name = script.get('script_name', '')
        additional = self.additional_input.text().strip()

        # Clear previous report
        self.report_text.clear()

        # Disable install button, enable stop button
        self.install_button.setEnabled(False)
        self.stop_button.setEnabled(True)

        # Create and start worker thread
        self.worker = SSHWorker(server_ip, password, script_name, additional)
        self.worker.output_received.connect(self.on_output_received)
        self.worker.status_changed.connect(self.on_status_changed)
        self.worker.finished_signal.connect(self.on_installation_finished)
        self.worker.start()

    def on_stop_clicked(self):
        """Handle stop button click."""
        if self.worker:
            self.worker.request_stop()
            self.stop_button.setEnabled(False)

    def on_output_received(self, text: str):
        """Handle output received from SSH."""
        self.report_text.moveCursor(QTextCursor.MoveOperation.End)
        self.report_text.insertPlainText(text)
        # Auto-scroll to bottom
        scrollbar = self.report_text.verticalScrollBar()
        scrollbar.setValue(scrollbar.maximum())

    def on_status_changed(self, status: str):
        """Handle status change."""
        self.setWindowTitle(f"{self.tr['window_title']} - {status}")

    def on_installation_finished(self, success: bool, message: str):
        """Handle installation completion."""
        self.install_button.setEnabled(True)
        self.stop_button.setEnabled(False)

        self.report_text.append("\n" + "-" * 50)
        if success:
            self.report_text.append(f"\n{self.tr['status_completed']}")
        else:
            self.report_text.append(f"\n{self.tr['status_error'].format(error=message)}")

        self.setWindowTitle(self.tr['window_title'])
        self.worker = None

    def clear_report(self):
        """Clear the report text."""
        self.report_text.clear()

    def on_language_changed(self, index: int):
        """Handle language selection change."""
        new_lang = self.lang_combo.itemData(index)
        if new_lang == self.lang:
            return

        # Update language
        self.lang = new_lang
        self.tr = TRANSLATIONS.get(new_lang, TRANSLATIONS[DEFAULT_LANG])

        # Reload scripts for the new language
        self.scripts = load_scripts(new_lang)

        # Update all UI text elements
        self.update_ui_text()

    def update_ui_text(self):
        """Update all UI text elements with current language."""
        # Window title
        self.setWindowTitle(self.tr['window_title'])

        # Language label
        self.lang_label.setText(self.tr['language_label'])

        # Input labels
        self.ip_label.setText(self.tr['server_ip'])
        self.password_label.setText(self.tr['server_password'])
        self.additional_label.setText(self.tr['additional_info'])

        # Software label
        self.software_label.setText(self.tr['software_list'])

        # Update software combo box with scripts in new language
        current_selection = self.software_combo.currentIndex()
        self.software_combo.clear()
        for script in self.scripts:
            display_text = script.get('name', '')
            self.software_combo.addItem(display_text, script)

        # Restore selection if possible
        if 0 <= current_selection < len(self.scripts):
            self.software_combo.setCurrentIndex(current_selection)
        elif self.scripts:
            self.software_combo.setCurrentIndex(0)

        # Update description
        self.on_script_selection_changed(self.software_combo.currentIndex())

        # Update buttons
        self.install_button.setText(self.tr['install_button'])
        self.stop_button.setText(self.tr['stop_button'])
        self.clear_button.setText(self.tr['clear_button'])

        # Update report label
        self.report_label.setText(self.tr['report_title'])

    def closeEvent(self, event):
        """Handle window close event."""
        if self.worker and self.worker.isRunning():
            reply = QMessageBox.question(
                self, 'Confirm Exit',
                'Installation is in progress. Are you sure you want to exit?',
                QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No,
                QMessageBox.StandardButton.No
            )

            if reply == QMessageBox.StandardButton.Yes:
                self.worker.request_stop()
                self.worker.wait(2000)
                event.accept()
            else:
                event.ignore()
        else:
            event.accept()


def setup_logging(debug: bool = False) -> None:
    """Configure logging for the application."""
    # Check for environment variable as well
    if os.environ.get('INSTALL_SCRIPTS_DEBUG', '').lower() in ('1', 'true', 'yes'):
        debug = True

    level = logging.DEBUG if debug else logging.WARNING
    log_format = '%(asctime)s - %(name)s - %(levelname)s - %(message)s'

    # Configure root logger
    logging.basicConfig(level=level, format=log_format)

    # Also log to file if in debug mode
    if debug:
        try:
            # Get a writable directory for the log file
            if getattr(sys, 'frozen', False):
                # For frozen executables, use user's home directory
                log_dir = os.path.expanduser('~')
            else:
                # For development, use current directory
                log_dir = os.getcwd()

            log_file = os.path.join(log_dir, 'install_scripts_debug.log')
            file_handler = logging.FileHandler(log_file, encoding='utf-8')
            file_handler.setLevel(logging.DEBUG)
            file_handler.setFormatter(logging.Formatter(log_format))
            logging.getLogger().addHandler(file_handler)
            logger.info(f"Debug logging enabled, log file: {log_file}")
        except Exception as e:
            logger.warning(f"Could not create log file: {e}")


def parse_args():
    """Parse command-line arguments."""
    parser = argparse.ArgumentParser(
        description='Install Scripts GUI - PyQt6 Application for installing software on remote servers'
    )
    parser.add_argument(
        '--lang',
        type=str,
        default=DEFAULT_LANG,
        choices=['ru', 'en'],
        help='Language for the interface (default: ru)'
    )
    parser.add_argument(
        '--debug',
        action='store_true',
        help='Enable debug logging (also via INSTALL_SCRIPTS_DEBUG=1 env var)'
    )
    return parser.parse_args()


def main():
    """Main entry point."""
    args = parse_args()

    # Setup logging before anything else
    setup_logging(args.debug)

    logger.info("Starting Install Scripts GUI")
    logger.debug(f"Python version: {sys.version}")
    logger.debug(f"sys.frozen: {getattr(sys, 'frozen', False)}")
    logger.debug(f"sys._MEIPASS: {getattr(sys, '_MEIPASS', 'Not set')}")

    app = QApplication(sys.argv)
    app.setApplicationName("Install Scripts GUI")

    window = MainWindow(lang=args.lang)
    window.show()

    sys.exit(app.exec())


if __name__ == '__main__':
    main()
