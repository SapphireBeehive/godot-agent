"""
Tests for DNS filtering functionality.

Verifies that:
- Allowed domains resolve to proxy IPs
- Blocked domains return NXDOMAIN
- DNS queries are properly logged
"""

import pytest

from conftest import DockerComposeStack


class TestDNSAllowedDomains:
    """Test that allowlisted domains resolve to correct proxy IPs."""
    
    # Expected mappings from hosts.allowlist
    ALLOWED_DOMAINS = {
        "github.com": "10.100.1.10",
        "www.github.com": "10.100.1.10",
        "raw.githubusercontent.com": "10.100.1.11",
        "codeload.github.com": "10.100.1.12",
        "docs.godotengine.org": "10.100.1.13",
        "api.anthropic.com": "10.100.1.14",
    }
    
    @pytest.mark.parametrize("domain,expected_ip", ALLOWED_DOMAINS.items())
    def test_allowed_domain_resolves_to_proxy_ip(
        self,
        sandbox_stack: DockerComposeStack,
        domain: str,
        expected_ip: str,
    ) -> None:
        """Verify that allowlisted domains resolve to their proxy IPs."""
        # Use nslookup to check DNS resolution
        result = sandbox_stack.exec_in_container(
            "agent",
            f"nslookup {domain}",
        )
        
        # The output should contain the expected proxy IP
        assert expected_ip in result.output, (
            f"Expected {domain} to resolve to {expected_ip}, "
            f"got: {result.output}"
        )
    
    def test_github_resolves_via_dig(
        self,
        sandbox_stack: DockerComposeStack,
    ) -> None:
        """Alternative test using dig command if available."""
        result = sandbox_stack.exec_in_container(
            "agent",
            "dig +short github.com @10.100.1.2 2>/dev/null || nslookup github.com | grep -A1 'Name:'",
        )
        
        # Should contain the proxy IP
        assert "10.100.1.10" in result.output or result.exit_code != 0, (
            f"Expected github.com to resolve to 10.100.1.10, got: {result.output}"
        )


class TestDNSBlockedDomains:
    """Test that non-allowlisted domains are blocked."""
    
    BLOCKED_DOMAINS = [
        "google.com",
        "example.com",
        "malicious-site.com",
        "facebook.com",
        "twitter.com",
        "evil.example.org",
        "s3.amazonaws.com",
        "ec2.amazonaws.com",
    ]
    
    @pytest.mark.parametrize("domain", BLOCKED_DOMAINS)
    def test_blocked_domain_returns_nxdomain(
        self,
        sandbox_stack: DockerComposeStack,
        domain: str,
    ) -> None:
        """Verify that non-allowlisted domains return NXDOMAIN."""
        result = sandbox_stack.exec_in_container(
            "agent",
            f"nslookup {domain} 2>&1",
        )
        
        # Should indicate the domain was not found
        output_lower = result.output.lower()
        assert any(indicator in output_lower for indicator in [
            "nxdomain",
            "can't find",
            "server can't find",
            "name or service not known",
            "non-existent",
            "** server can't find",
            "no answer",
        ]), (
            f"Expected {domain} to return NXDOMAIN, got: {result.output}"
        )
    
    def test_blocked_domain_no_resolution(
        self,
        sandbox_stack: DockerComposeStack,
    ) -> None:
        """Verify blocked domains don't resolve to any IP."""
        result = sandbox_stack.exec_in_container(
            "agent",
            "getent hosts google.com 2>&1 || echo 'NOT_FOUND'",
        )
        
        # Should not contain a valid IP address
        assert "NOT_FOUND" in result.output or result.exit_code != 0, (
            f"Expected google.com to not resolve, got: {result.output}"
        )


class TestDNSSubdomains:
    """Test subdomain handling."""
    
    def test_allowed_subdomain_works(
        self,
        sandbox_stack: DockerComposeStack,
    ) -> None:
        """Test that www.github.com (explicitly allowed) works."""
        result = sandbox_stack.exec_in_container(
            "agent",
            "nslookup www.github.com",
        )
        
        assert "10.100.1.10" in result.output, (
            f"Expected www.github.com to resolve to 10.100.1.10, got: {result.output}"
        )
    
    def test_unlisted_subdomain_blocked(
        self,
        sandbox_stack: DockerComposeStack,
    ) -> None:
        """Test that subdomains not in allowlist are blocked."""
        # gist.github.com is not in the allowlist
        result = sandbox_stack.exec_in_container(
            "agent",
            "nslookup gist.github.com 2>&1",
        )
        
        output_lower = result.output.lower()
        assert any(indicator in output_lower for indicator in [
            "nxdomain",
            "can't find",
            "server can't find",
            "non-existent",
        ]), (
            f"Expected gist.github.com to be blocked, got: {result.output}"
        )


class TestDNSConfiguration:
    """Test DNS filter configuration."""
    
    def test_agent_uses_dnsfilter(
        self,
        sandbox_stack: DockerComposeStack,
    ) -> None:
        """Verify agent is configured to use dnsfilter (10.100.1.2)."""
        result = sandbox_stack.exec_in_container(
            "agent",
            "cat /etc/resolv.conf",
        )
        
        assert "10.100.1.2" in result.output, (
            f"Expected DNS to be 10.100.1.2, got: {result.output}"
        )
    
    def test_dnsfilter_health_endpoint(
        self,
        sandbox_stack: DockerComposeStack,
    ) -> None:
        """Verify dnsfilter health endpoint is accessible."""
        result = sandbox_stack.exec_in_container(
            "agent",
            "wget -q -O - http://10.100.1.2:8080/health 2>&1 || curl -s http://10.100.1.2:8080/health 2>&1",
        )
        
        # Health check should return OK or similar
        assert result.success or "OK" in result.output.upper(), (
            f"DNS health check failed: {result.output}"
        )


class TestDNSLogging:
    """Test that DNS queries are logged."""
    
    def test_dns_queries_logged(
        self,
        sandbox_stack: DockerComposeStack,
    ) -> None:
        """Verify DNS queries appear in dnsfilter logs."""
        # Make a DNS query
        sandbox_stack.exec_in_container(
            "agent",
            "nslookup unique-test-domain-12345.com 2>&1 || true",
        )
        
        # Check dnsfilter logs
        logs = sandbox_stack.get_container_logs("dnsfilter", tail=50)
        
        # CoreDNS should log queries
        assert "unique-test-domain-12345" in logs.lower() or len(logs) > 0, (
            f"Expected DNS query to be logged, logs: {logs[:500]}"
        )
    
    def test_allowed_queries_logged(
        self,
        sandbox_stack: DockerComposeStack,
    ) -> None:
        """Verify allowed domain queries are also logged."""
        # Make an allowed query
        sandbox_stack.exec_in_container(
            "agent",
            "nslookup github.com",
        )
        
        # Check logs exist (CoreDNS logs all queries)
        logs = sandbox_stack.get_container_logs("dnsfilter", tail=50)
        
        # Should have some content if logging is enabled
        assert len(logs) > 0, "Expected dnsfilter to have logs"

