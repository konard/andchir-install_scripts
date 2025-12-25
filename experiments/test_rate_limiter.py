#!/usr/bin/env python3
"""
Test script for the Rate Limiter module.

This script tests the rate limiting functionality including:
- Request recording
- Rate limit enforcement
- IP blocking/unblocking
- Database persistence

Usage:
    python test_rate_limiter.py
"""

import os
import sys
import time
import tempfile
import unittest

# Add the api directory to the path for imports
sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), 'api'))

from rate_limiter import RateLimiter


class TestRateLimiter(unittest.TestCase):
    """Test cases for the RateLimiter class."""

    def setUp(self):
        """Set up test fixtures."""
        # Create a temporary database file for testing
        self.temp_db = tempfile.NamedTemporaryFile(suffix='.db', delete=False)
        self.temp_db.close()
        self.db_path = self.temp_db.name

        # Create rate limiter with low limits for testing
        self.limiter = RateLimiter(
            db_path=self.db_path,
            max_requests=3,
            time_window=60,
            enabled=True
        )

    def tearDown(self):
        """Clean up test fixtures."""
        # Remove temporary database file
        if os.path.exists(self.db_path):
            os.unlink(self.db_path)

    def test_rate_limiter_disabled(self):
        """Test that disabled rate limiter allows all requests."""
        limiter = RateLimiter(enabled=False)

        # Should always return True and 0 count
        allowed, count, reason = limiter.record_request('192.168.1.1')
        self.assertTrue(allowed)
        self.assertEqual(count, 0)
        self.assertIsNone(reason)

    def test_request_recording(self):
        """Test that requests are properly recorded."""
        test_ip = '10.0.0.1'

        # Record first request
        allowed, count, reason = self.limiter.record_request(test_ip)
        self.assertTrue(allowed)
        self.assertEqual(count, 1)
        self.assertIsNone(reason)

        # Record second request
        allowed, count, reason = self.limiter.record_request(test_ip)
        self.assertTrue(allowed)
        self.assertEqual(count, 2)
        self.assertIsNone(reason)

        # Check request count
        self.assertEqual(self.limiter.get_ip_request_count(test_ip), 2)

    def test_rate_limit_enforcement(self):
        """Test that rate limit is enforced after max requests."""
        test_ip = '10.0.0.2'

        # Make max_requests (3) requests - all should be allowed
        for i in range(3):
            allowed, count, reason = self.limiter.record_request(test_ip)
            self.assertTrue(allowed, f"Request {i+1} should be allowed")

        # The 4th request should trigger rate limit
        allowed, count, reason = self.limiter.record_request(test_ip)
        self.assertFalse(allowed)
        self.assertIsNotNone(reason)
        self.assertIn('Rate limit exceeded', reason)

    def test_manual_ip_blocking(self):
        """Test manual IP blocking and unblocking."""
        test_ip = '10.0.0.3'

        # Manually block IP
        result = self.limiter.block_ip(test_ip, reason='Test block', permanent=True)
        self.assertTrue(result)

        # Check if IP is blocked
        is_blocked, reason = self.limiter.is_blocked(test_ip)
        self.assertTrue(is_blocked)
        self.assertEqual(reason, 'Test block')

        # Request should be denied
        allowed, count, reason = self.limiter.record_request(test_ip)
        self.assertFalse(allowed)
        self.assertEqual(reason, 'Test block')

        # Unblock IP
        result = self.limiter.unblock_ip(test_ip)
        self.assertTrue(result)

        # Check if IP is unblocked
        is_blocked, reason = self.limiter.is_blocked(test_ip)
        self.assertFalse(is_blocked)
        self.assertIsNone(reason)

    def test_temporary_blocking(self):
        """Test temporary IP blocking with duration."""
        test_ip = '10.0.0.4'

        # Block IP for 1 hour
        result = self.limiter.block_ip(test_ip, reason='Temporary block', duration_hours=1)
        self.assertTrue(result)

        # Check if IP is blocked
        is_blocked, reason = self.limiter.is_blocked(test_ip)
        self.assertTrue(is_blocked)

    def test_get_blocked_ips(self):
        """Test retrieving list of blocked IPs."""
        # Block some IPs
        self.limiter.block_ip('10.0.0.10', reason='Block 1', permanent=True)
        self.limiter.block_ip('10.0.0.11', reason='Block 2', permanent=False, duration_hours=1)

        # Get blocked IPs
        blocked = self.limiter.get_blocked_ips()
        self.assertEqual(len(blocked), 2)

        # Check IPs are in the list
        blocked_ips = [b['ip_address'] for b in blocked]
        self.assertIn('10.0.0.10', blocked_ips)
        self.assertIn('10.0.0.11', blocked_ips)

    def test_request_stats(self):
        """Test retrieving request statistics."""
        test_ip1 = '10.0.0.20'
        test_ip2 = '10.0.0.21'

        # Record some requests
        self.limiter.record_request(test_ip1)
        self.limiter.record_request(test_ip1)
        self.limiter.record_request(test_ip2)

        # Get stats for all IPs
        stats = self.limiter.get_request_stats()
        self.assertEqual(len(stats), 3)

        # Get stats for specific IP
        stats = self.limiter.get_request_stats(ip_address=test_ip1)
        self.assertEqual(len(stats), 2)

    def test_unblock_nonexistent_ip(self):
        """Test unblocking an IP that was not blocked."""
        result = self.limiter.unblock_ip('192.168.99.99')
        self.assertFalse(result)

    def test_multiple_ips_independent(self):
        """Test that rate limits are independent for different IPs."""
        ip1 = '10.0.0.30'
        ip2 = '10.0.0.31'

        # Max out requests for ip1
        for _ in range(3):
            self.limiter.record_request(ip1)

        # ip1 should be at limit now
        allowed, _, _ = self.limiter.record_request(ip1)
        self.assertFalse(allowed)

        # ip2 should still be able to make requests
        allowed, count, reason = self.limiter.record_request(ip2)
        self.assertTrue(allowed)
        self.assertEqual(count, 1)


def run_integration_test():
    """Run a simple integration test showing rate limiter in action."""
    print("=" * 60)
    print("Rate Limiter Integration Test")
    print("=" * 60)

    # Create temporary database
    temp_db = tempfile.NamedTemporaryFile(suffix='.db', delete=False)
    temp_db.close()

    try:
        # Create rate limiter with 5 requests per minute limit
        limiter = RateLimiter(
            db_path=temp_db.name,
            max_requests=5,
            time_window=60,
            enabled=True
        )

        test_ip = '192.168.1.100'
        print(f"\nTest IP: {test_ip}")
        print(f"Max requests per minute: 5")
        print("-" * 40)

        # Simulate requests
        for i in range(7):
            allowed, count, reason = limiter.record_request(test_ip, '/api/install')

            if allowed:
                print(f"Request {i+1}: ALLOWED (count: {count})")
            else:
                print(f"Request {i+1}: BLOCKED - {reason}")

        print("-" * 40)

        # Check blocked IPs
        blocked = limiter.get_blocked_ips()
        print(f"\nBlocked IPs: {len(blocked)}")
        for b in blocked:
            print(f"  - {b['ip_address']}: {b['reason']}")

        # Test manual block
        print("\n" + "-" * 40)
        print("Testing manual block...")
        limiter.block_ip('10.10.10.10', reason='Suspicious activity', permanent=True)
        blocked = limiter.get_blocked_ips()
        print(f"Blocked IPs after manual block: {len(blocked)}")

        # Test unblock
        print("\n" + "-" * 40)
        print("Testing unblock...")
        limiter.unblock_ip('10.10.10.10')
        blocked = limiter.get_blocked_ips()
        print(f"Blocked IPs after unblock: {len(blocked)}")

        print("\n" + "=" * 60)
        print("Integration test completed!")
        print("=" * 60)

    finally:
        # Cleanup
        os.unlink(temp_db.name)


if __name__ == '__main__':
    # Run unit tests
    print("Running unit tests...\n")
    unittest.main(verbosity=2, exit=False)

    # Run integration test
    print("\n")
    run_integration_test()
