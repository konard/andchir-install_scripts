#!/usr/bin/env python3
"""
Rate Limiter Module for Install Scripts API

This module provides rate limiting functionality using SQLite database
to track IP addresses and prevent malicious use of the API.

The rate limiter:
- Records all IP addresses accessing protected endpoints
- Blocks IPs that exceed the configured request limit per minute
- Stores data in a local SQLite database
- Can be enabled/disabled via environment variables
"""

import os
import sqlite3
import time
import threading
import logging
from datetime import datetime, timedelta
from contextlib import contextmanager

logger = logging.getLogger(__name__)


class RateLimiter:
    """
    Rate limiter that tracks IP addresses using SQLite database.

    Attributes:
        enabled: Whether rate limiting is enabled
        db_path: Path to the SQLite database file
        max_requests: Maximum requests allowed per time window
        time_window: Time window in seconds (default: 60 = 1 minute)
    """

    def __init__(self, db_path='rate_limiter.db', max_requests=10, time_window=60, enabled=True):
        """
        Initialize the rate limiter.

        Args:
            db_path: Path to SQLite database file
            max_requests: Maximum allowed requests per time window
            time_window: Time window in seconds
            enabled: Whether rate limiting is enabled
        """
        self.enabled = enabled
        self.db_path = db_path
        self.max_requests = max_requests
        self.time_window = time_window
        self._lock = threading.Lock()

        if self.enabled:
            self._init_database()
            logger.info(f"Rate limiter initialized: max {max_requests} requests per {time_window} seconds")
        else:
            logger.info("Rate limiter is disabled")

    def _init_database(self):
        """Initialize the SQLite database with required tables."""
        with self._get_connection() as conn:
            cursor = conn.cursor()

            # Table to track request history
            cursor.execute('''
                CREATE TABLE IF NOT EXISTS request_log (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    ip_address TEXT NOT NULL,
                    endpoint TEXT NOT NULL,
                    timestamp REAL NOT NULL,
                    created_at TEXT DEFAULT CURRENT_TIMESTAMP
                )
            ''')

            # Table for blocked IPs (manual or automatic blocking)
            cursor.execute('''
                CREATE TABLE IF NOT EXISTS blocked_ips (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    ip_address TEXT NOT NULL UNIQUE,
                    reason TEXT,
                    blocked_at TEXT DEFAULT CURRENT_TIMESTAMP,
                    blocked_until TEXT,
                    is_permanent INTEGER DEFAULT 0
                )
            ''')

            # Index for faster lookups
            cursor.execute('''
                CREATE INDEX IF NOT EXISTS idx_request_log_ip_timestamp
                ON request_log(ip_address, timestamp)
            ''')

            cursor.execute('''
                CREATE INDEX IF NOT EXISTS idx_blocked_ips_ip
                ON blocked_ips(ip_address)
            ''')

            conn.commit()
            logger.debug("Rate limiter database initialized")

    @contextmanager
    def _get_connection(self):
        """
        Context manager for database connections.

        Yields:
            sqlite3.Connection: Database connection
        """
        conn = sqlite3.connect(self.db_path, timeout=10)
        conn.row_factory = sqlite3.Row
        try:
            yield conn
        finally:
            conn.close()

    def _is_blocked_internal(self, cursor, ip_address):
        """
        Internal method to check if an IP is blocked (without locking).

        Args:
            cursor: Database cursor
            ip_address: IP address to check

        Returns:
            tuple: (is_blocked: bool, reason: str or None)
        """
        cursor.execute('''
            SELECT reason, blocked_until, is_permanent
            FROM blocked_ips
            WHERE ip_address = ?
        ''', (ip_address,))

        row = cursor.fetchone()

        if row is None:
            return False, None

        # Check if permanent block
        if row['is_permanent']:
            return True, row['reason']

        # Check if temporary block has expired
        if row['blocked_until']:
            blocked_until = datetime.fromisoformat(row['blocked_until'])
            if datetime.now() > blocked_until:
                # Block has expired, remove it
                cursor.execute('''
                    DELETE FROM blocked_ips WHERE ip_address = ?
                ''', (ip_address,))
                return False, None

        return True, row['reason']

    def is_blocked(self, ip_address):
        """
        Check if an IP address is currently blocked.

        Args:
            ip_address: IP address to check

        Returns:
            tuple: (is_blocked: bool, reason: str or None)
        """
        if not self.enabled:
            return False, None

        with self._lock:
            with self._get_connection() as conn:
                cursor = conn.cursor()
                result = self._is_blocked_internal(cursor, ip_address)
                conn.commit()
                return result

    def record_request(self, ip_address, endpoint='/api/install'):
        """
        Record a request from an IP address and check rate limit.

        Args:
            ip_address: IP address making the request
            endpoint: API endpoint being accessed

        Returns:
            tuple: (allowed: bool, requests_count: int, reason: str or None)
        """
        if not self.enabled:
            return True, 0, None

        current_time = time.time()

        with self._lock:
            with self._get_connection() as conn:
                cursor = conn.cursor()

                # First check if IP is already blocked (use internal method to avoid deadlock)
                is_blocked, reason = self._is_blocked_internal(cursor, ip_address)
                if is_blocked:
                    conn.commit()
                    return False, 0, reason

                # Record the current request
                cursor.execute('''
                    INSERT INTO request_log (ip_address, endpoint, timestamp)
                    VALUES (?, ?, ?)
                ''', (ip_address, endpoint, current_time))

                # Count requests in the time window
                window_start = current_time - self.time_window
                cursor.execute('''
                    SELECT COUNT(*) as count
                    FROM request_log
                    WHERE ip_address = ? AND timestamp > ?
                ''', (ip_address, window_start))

                count = cursor.fetchone()['count']

                # Clean up old records (older than 1 hour) to prevent database bloat
                cleanup_time = current_time - 3600
                cursor.execute('''
                    DELETE FROM request_log WHERE timestamp < ?
                ''', (cleanup_time,))

                conn.commit()

                # Check if rate limit exceeded
                if count > self.max_requests:
                    # Auto-block IP for 1 hour
                    blocked_until = datetime.now() + timedelta(hours=1)
                    reason = f'Rate limit exceeded: {count} requests in {self.time_window} seconds'

                    cursor.execute('''
                        INSERT OR REPLACE INTO blocked_ips (ip_address, reason, blocked_until, is_permanent)
                        VALUES (?, ?, ?, 0)
                    ''', (ip_address, reason, blocked_until.isoformat()))
                    conn.commit()

                    logger.warning(f"IP {ip_address} blocked: {reason}")
                    return False, count, reason

                return True, count, None

    def block_ip(self, ip_address, reason='Manual block', permanent=False, duration_hours=None):
        """
        Manually block an IP address.

        Args:
            ip_address: IP address to block
            reason: Reason for blocking
            permanent: Whether the block is permanent
            duration_hours: Duration of block in hours (if not permanent)

        Returns:
            bool: True if successfully blocked
        """
        if not self.enabled:
            return False

        with self._lock:
            with self._get_connection() as conn:
                cursor = conn.cursor()

                blocked_until = None
                if not permanent and duration_hours:
                    blocked_until = (datetime.now() + timedelta(hours=duration_hours)).isoformat()

                cursor.execute('''
                    INSERT OR REPLACE INTO blocked_ips (ip_address, reason, blocked_until, is_permanent)
                    VALUES (?, ?, ?, ?)
                ''', (ip_address, reason, blocked_until, 1 if permanent else 0))

                conn.commit()
                logger.info(f"IP {ip_address} blocked: {reason}")
                return True

    def unblock_ip(self, ip_address):
        """
        Unblock an IP address.

        Args:
            ip_address: IP address to unblock

        Returns:
            bool: True if successfully unblocked
        """
        if not self.enabled:
            return False

        with self._lock:
            with self._get_connection() as conn:
                cursor = conn.cursor()
                cursor.execute('''
                    DELETE FROM blocked_ips WHERE ip_address = ?
                ''', (ip_address,))
                conn.commit()

                if cursor.rowcount > 0:
                    logger.info(f"IP {ip_address} unblocked")
                    return True
                return False

    def get_blocked_ips(self):
        """
        Get list of all currently blocked IPs.

        Returns:
            list: List of dictionaries with blocked IP info
        """
        if not self.enabled:
            return []

        with self._get_connection() as conn:
            cursor = conn.cursor()
            cursor.execute('''
                SELECT ip_address, reason, blocked_at, blocked_until, is_permanent
                FROM blocked_ips
                ORDER BY blocked_at DESC
            ''')

            return [dict(row) for row in cursor.fetchall()]

    def get_request_stats(self, ip_address=None, limit=100):
        """
        Get request statistics.

        Args:
            ip_address: Optional IP to filter by
            limit: Maximum number of records to return

        Returns:
            list: List of request log entries
        """
        if not self.enabled:
            return []

        with self._get_connection() as conn:
            cursor = conn.cursor()

            if ip_address:
                cursor.execute('''
                    SELECT ip_address, endpoint, timestamp, created_at
                    FROM request_log
                    WHERE ip_address = ?
                    ORDER BY timestamp DESC
                    LIMIT ?
                ''', (ip_address, limit))
            else:
                cursor.execute('''
                    SELECT ip_address, endpoint, timestamp, created_at
                    FROM request_log
                    ORDER BY timestamp DESC
                    LIMIT ?
                ''', (limit,))

            return [dict(row) for row in cursor.fetchall()]

    def get_ip_request_count(self, ip_address):
        """
        Get the number of requests from an IP in the current time window.

        Args:
            ip_address: IP address to check

        Returns:
            int: Number of requests in current time window
        """
        if not self.enabled:
            return 0

        current_time = time.time()
        window_start = current_time - self.time_window

        with self._get_connection() as conn:
            cursor = conn.cursor()
            cursor.execute('''
                SELECT COUNT(*) as count
                FROM request_log
                WHERE ip_address = ? AND timestamp > ?
            ''', (ip_address, window_start))

            return cursor.fetchone()['count']

    def cleanup_old_records(self, hours=24):
        """
        Clean up old request log records.

        Args:
            hours: Delete records older than this many hours
        """
        if not self.enabled:
            return

        with self._lock:
            with self._get_connection() as conn:
                cursor = conn.cursor()
                cleanup_time = time.time() - (hours * 3600)
                cursor.execute('''
                    DELETE FROM request_log WHERE timestamp < ?
                ''', (cleanup_time,))
                conn.commit()

                if cursor.rowcount > 0:
                    logger.info(f"Cleaned up {cursor.rowcount} old request log records")
