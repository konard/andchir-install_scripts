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
from typing import Optional

from PyQt6.QtWidgets import (
    QApplication, QMainWindow, QWidget, QVBoxLayout, QHBoxLayout,
    QLabel, QLineEdit, QPushButton, QTextEdit, QListWidget,
    QListWidgetItem, QGroupBox, QMessageBox, QSplitter, QFrame
)
from PyQt6.QtCore import Qt, QThread, pyqtSignal, QTimer
from PyQt6.QtGui import QFont, QIcon

# SSH imports
try:
    import paramiko
    SSH_AVAILABLE = True
except ImportError:
    SSH_AVAILABLE = False
    paramiko = None


# Configuration
SCRIPTS_BASE_URL = 'https://raw.githubusercontent.com/andchir/install_scripts/refs/heads/main/scripts'
SSH_DEFAULT_PORT = 22
SSH_DEFAULT_TIMEOUT = 30
DEFAULT_LANG = 'ru'

# Translations
TRANSLATIONS = {
    'ru': {
        'window_title': 'Install Scripts - Установка ПО',
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
    },
    'en': {
        'window_title': 'Install Scripts - Software Installation',
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
    }
}


def strip_ansi_codes(text: Optional[str]) -> Optional[str]:
    """Remove ANSI escape codes from text."""
    if text is None:
        return None
    ansi_escape = re.compile(r'\x1B(?:[@-Z\\-_]|\[[0-?]*[ -/]*[@-~])')
    return ansi_escape.sub('', text)


def get_data_file_path(lang: str) -> str:
    """Get the path to the data file for the specified language."""
    # Try to find the data file relative to the script location
    script_dir = os.path.dirname(os.path.abspath(__file__))
    parent_dir = os.path.dirname(script_dir)

    data_file = os.path.join(parent_dir, f'data_{lang}.json')
    if os.path.exists(data_file):
        return data_file

    # Fall back to default language
    default_file = os.path.join(parent_dir, f'data_{DEFAULT_LANG}.json')
    if os.path.exists(default_file):
        return default_file

    return ''


def load_scripts(lang: str) -> list:
    """Load scripts list from the data file."""
    data_file = get_data_file_path(lang)
    if not data_file or not os.path.exists(data_file):
        return []

    try:
        with open(data_file, 'r', encoding='utf-8') as f:
            return json.load(f)
    except (json.JSONDecodeError, IOError):
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

        self.init_ui()

    def init_ui(self):
        """Initialize the user interface."""
        self.setWindowTitle(self.tr['window_title'])
        self.setMinimumSize(800, 600)

        # Central widget
        central_widget = QWidget()
        self.setCentralWidget(central_widget)

        # Main layout with splitter
        main_layout = QVBoxLayout(central_widget)

        splitter = QSplitter(Qt.Orientation.Vertical)
        main_layout.addWidget(splitter)

        # Top section - Input fields
        top_widget = QWidget()
        top_layout = QVBoxLayout(top_widget)
        top_layout.setContentsMargins(10, 10, 10, 10)

        # Server IP
        ip_layout = QHBoxLayout()
        ip_label = QLabel(self.tr['server_ip'])
        ip_label.setMinimumWidth(250)
        self.ip_input = QLineEdit()
        self.ip_input.setPlaceholderText("192.168.1.100")
        ip_layout.addWidget(ip_label)
        ip_layout.addWidget(self.ip_input)
        top_layout.addLayout(ip_layout)

        # Server Password
        password_layout = QHBoxLayout()
        password_label = QLabel(self.tr['server_password'])
        password_label.setMinimumWidth(250)
        self.password_input = QLineEdit()
        self.password_input.setEchoMode(QLineEdit.EchoMode.Password)
        password_layout.addWidget(password_label)
        password_layout.addWidget(self.password_input)
        top_layout.addLayout(password_layout)

        # Additional info
        additional_layout = QHBoxLayout()
        additional_label = QLabel(self.tr['additional_info'])
        additional_label.setMinimumWidth(250)
        self.additional_input = QLineEdit()
        self.additional_input.setPlaceholderText("example.com")
        additional_layout.addWidget(additional_label)
        additional_layout.addWidget(self.additional_input)
        top_layout.addLayout(additional_layout)

        # Software list
        software_group = QGroupBox(self.tr['software_list'])
        software_layout = QVBoxLayout(software_group)

        self.software_list = QListWidget()
        self.software_list.setSelectionMode(QListWidget.SelectionMode.SingleSelection)

        # Populate software list
        for script in self.scripts:
            item = QListWidgetItem()
            item.setText(f"{script.get('name', '')} - {script.get('description', '')}")
            item.setData(Qt.ItemDataRole.UserRole, script.get('script_name', ''))
            item.setToolTip(script.get('info', ''))
            self.software_list.addItem(item)

        software_layout.addWidget(self.software_list)
        top_layout.addWidget(software_group)

        # Buttons
        button_layout = QHBoxLayout()

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
        report_group = QGroupBox(self.tr['report_title'])
        report_layout = QVBoxLayout(report_group)

        self.report_text = QTextEdit()
        self.report_text.setReadOnly(True)
        self.report_text.setFont(QFont("Courier New", 10))
        report_layout.addWidget(self.report_text)

        # Clear button
        clear_button = QPushButton(self.tr['clear_button'])
        clear_button.clicked.connect(self.clear_report)
        report_layout.addWidget(clear_button)

        splitter.addWidget(report_group)

        # Set initial splitter sizes
        splitter.setSizes([400, 200])

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

        selected_items = self.software_list.selectedItems()
        if not selected_items:
            QMessageBox.warning(self, "Error", self.tr['error_no_script'])
            return

        script_name = selected_items[0].data(Qt.ItemDataRole.UserRole)
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
        self.report_text.moveCursor(self.report_text.textCursor().End)
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
    return parser.parse_args()


def main():
    """Main entry point."""
    args = parse_args()

    app = QApplication(sys.argv)
    app.setApplicationName("Install Scripts GUI")

    window = MainWindow(lang=args.lang)
    window.show()

    sys.exit(app.exec())


if __name__ == '__main__':
    main()
