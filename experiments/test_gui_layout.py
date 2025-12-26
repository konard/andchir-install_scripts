#!/usr/bin/env python3
"""
Test script for GUI layout improvements.
This script creates a minimal version of the GUI to test layout changes.
"""

import sys
from PyQt6.QtWidgets import (
    QApplication, QMainWindow, QWidget, QVBoxLayout, QHBoxLayout,
    QLabel, QLineEdit, QPushButton, QTextEdit, QComboBox,
    QGroupBox, QSplitter, QFrame
)
from PyQt6.QtCore import Qt
from PyQt6.QtGui import QFont


class TestMainWindow(QMainWindow):
    """Test window for GUI layout experiments."""

    def __init__(self):
        super().__init__()
        self.init_ui()

    def init_ui(self):
        """Initialize the user interface."""
        self.setWindowTitle('Layout Test - Install Scripts GUI')
        self.setMinimumSize(800, 600)

        # Central widget
        central_widget = QWidget()
        self.setCentralWidget(central_widget)

        # Main layout
        main_layout = QVBoxLayout(central_widget)
        main_layout.setContentsMargins(10, 10, 10, 10)  # Consistent outer margin

        # Language selector at the top right
        lang_layout = QHBoxLayout()
        lang_layout.addStretch()
        lang_label = QLabel('Language:')
        lang_combo = QComboBox()
        lang_combo.addItem('English', 'en')
        lang_combo.addItem('Русский', 'ru')
        lang_layout.addWidget(lang_label)
        lang_layout.addWidget(lang_combo)
        main_layout.addLayout(lang_layout)

        # Splitter for resizable sections
        splitter = QSplitter(Qt.Orientation.Vertical)
        main_layout.addWidget(splitter)

        # Top section - Input fields
        top_widget = QWidget()
        top_layout = QVBoxLayout(top_widget)
        top_layout.setContentsMargins(0, 0, 0, 0)

        # Server inputs section (with frame/border)
        inputs_frame = QFrame()
        inputs_frame.setFrameShape(QFrame.Shape.StyledPanel)
        inputs_frame.setFrameShadow(QFrame.Shadow.Raised)
        inputs_frame.setStyleSheet("""
            QFrame {
                border: 1px solid #ddd;
                border-radius: 4px;
                padding: 10px;
                background-color: white;
            }
        """)
        inputs_layout = QVBoxLayout(inputs_frame)
        inputs_layout.setContentsMargins(10, 10, 10, 10)  # Same padding top and bottom

        # Server IP
        ip_layout = QHBoxLayout()
        ip_label = QLabel('Server IP address:')
        ip_label.setMinimumWidth(250)
        ip_input = QLineEdit()
        ip_input.setPlaceholderText("192.168.1.100")
        ip_layout.addWidget(ip_label)
        ip_layout.addWidget(ip_input)
        inputs_layout.addLayout(ip_layout)

        # Server Password
        password_layout = QHBoxLayout()
        password_label = QLabel('SSH root password:')
        password_label.setMinimumWidth(250)
        password_input = QLineEdit()
        password_input.setEchoMode(QLineEdit.EchoMode.Password)
        password_layout.addWidget(password_label)
        password_layout.addWidget(password_input)
        inputs_layout.addLayout(password_layout)

        # Additional info
        additional_layout = QHBoxLayout()
        additional_label = QLabel('Additional information:')
        additional_label.setMinimumWidth(250)
        additional_input = QLineEdit()
        additional_input.setPlaceholderText("example.com")
        additional_layout.addWidget(additional_label)
        additional_layout.addWidget(additional_input)
        inputs_layout.addLayout(additional_layout)

        top_layout.addWidget(inputs_frame)

        # Software selection section (with frame/border)
        software_frame = QFrame()
        software_frame.setFrameShape(QFrame.Shape.StyledPanel)
        software_frame.setStyleSheet("""
            QFrame {
                border: 1px solid #ddd;
                border-radius: 4px;
                background-color: white;
            }
        """)
        software_inner_layout = QVBoxLayout(software_frame)
        software_inner_layout.setContentsMargins(10, 10, 10, 10)  # Same padding all around

        software_label = QLabel('Software to install on server:')
        software_inner_layout.addWidget(software_label)

        # Dropdown
        software_combo = QComboBox()
        software_combo.setMinimumHeight(30)
        software_combo.addItem('wireguard/wireguard-ui')
        software_combo.addItem('docker/docker-ce')
        software_inner_layout.addWidget(software_combo)

        # Description text area
        description_label = QTextEdit()
        description_label.setReadOnly(True)
        description_label.setMinimumHeight(70)
        description_label.setMaximumHeight(80)
        description_label.setStyleSheet("""
            QTextEdit {
                background-color: #f5f5f5;
                padding: 5px;
                border: 1px solid #ddd;
                border-radius: 4px;
            }
        """)
        description_label.setPlainText("VPN-сервер WireGuard с веб-интерфейсом WireGuard-UI для управления\n\nНеобходимый параметр: доменное имя")
        software_inner_layout.addWidget(description_label)

        top_layout.addWidget(software_frame)

        # Spacing between sections and buttons
        top_layout.addSpacing(10)

        # Buttons section - OUTSIDE the bordered area
        button_layout = QHBoxLayout()
        button_layout.setContentsMargins(0, 0, 0, 0)

        install_button = QPushButton('Install')
        install_button.setMinimumHeight(40)

        stop_button = QPushButton('Stop')
        stop_button.setMinimumHeight(40)
        stop_button.setEnabled(False)

        button_layout.addWidget(install_button)
        button_layout.addWidget(stop_button)
        top_layout.addLayout(button_layout)

        splitter.addWidget(top_widget)

        # Bottom section - Report (with frame/border)
        report_frame = QFrame()
        report_frame.setFrameShape(QFrame.Shape.StyledPanel)
        report_frame.setStyleSheet("""
            QFrame {
                border: 1px solid #ddd;
                border-radius: 4px;
                background-color: white;
            }
        """)
        report_inner_layout = QVBoxLayout(report_frame)
        report_inner_layout.setContentsMargins(10, 10, 10, 10)  # Same padding all around

        report_label = QLabel('Report')
        report_label.setStyleSheet("font-weight: bold; border: none;")
        report_inner_layout.addWidget(report_label)

        report_text = QTextEdit()
        report_text.setReadOnly(True)
        report_text.setFont(QFont("Courier New", 10))
        report_text.setMinimumHeight(200)
        report_text.setStyleSheet("border: 1px solid #ddd; border-radius: 4px;")
        report_inner_layout.addWidget(report_text)

        # Clear button - OUTSIDE the bordered report area
        splitter.addWidget(report_frame)

        # Clear button at the bottom, outside the report frame
        clear_button = QPushButton('Clear')
        main_layout.addWidget(clear_button)

        # Set initial splitter sizes
        splitter.setSizes([350, 250])


def main():
    """Main entry point."""
    app = QApplication(sys.argv)
    app.setApplicationName("Layout Test")

    window = TestMainWindow()
    window.show()

    sys.exit(app.exec())


if __name__ == '__main__':
    main()
