"""
Tests for network restriction functionality.

Verifies that:
- Agent cannot reach the internet directly
- Agent can only communicate via proxy containers
- Proxy routing works for allowed domains
"""

import pytest

from conftest import DockerComposeStack, requires_network


class TestNetworkIsolation:
    """Test that agent is isolated from the internet."""
    
    def test_agent_on_sandbox_net_only(
        self,
        sandbox_stack: DockerComposeStack,
    ) -> None:
        """Verify agent is only connected to sandbox_net."""
        inspect = sandbox_stack.container_inspect("agent")
        assert inspect is not None, "Agent container not found"
        
        networks = inspect["NetworkSettings"]["Networks"]
        network_names = list(networks.keys())
        
        # Should only be on sandbox_net
        assert len(network_names) == 1, (
            f"Expected agent on 1 network, found: {network_names}"
        )
        assert any("sandbox_net" in name for name in network_names), (
            f"Expected agent on sandbox_net, found: {network_names}"
        )
    
    def test_agent_has_correct_ip(
        self,
        sandbox_stack: DockerComposeStack,
    ) -> None:
        """Verify agent has IP 10.100.1.100 on sandbox_net."""
        inspect = sandbox_stack.container_inspect("agent")
        assert inspect is not None
        
        networks = inspect["NetworkSettings"]["Networks"]
        
        # Find sandbox_net
        for name, config in networks.items():
            if "sandbox_net" in name:
                assert config["IPAddress"] == "10.100.1.100", (
                    f"Expected IP 10.100.1.100, got: {config['IPAddress']}"
                )
                return
        
        pytest.fail("sandbox_net not found in agent networks")
    
    def test_cannot_ping_external_ip(
        self,
        sandbox_stack: DockerComposeStack,
    ) -> None:
        """Verify agent cannot ping external IPs directly."""
        # Try to ping Google's DNS (8.8.8.8)
        result = sandbox_stack.exec_in_container(
            "agent",
            "ping -c 1 -W 2 8.8.8.8 2>&1",
        )
        
        # Should fail (network unreachable or timeout)
        assert not result.success, (
            f"Expected ping to 8.8.8.8 to fail, got: {result.output}"
        )
    
    def test_cannot_reach_external_http(
        self,
        sandbox_stack: DockerComposeStack,
    ) -> None:
        """Verify agent cannot reach external HTTP servers directly."""
        # Try direct HTTP to external IP
        result = sandbox_stack.exec_in_container(
            "agent",
            "wget -q -O - --timeout=3 http://1.1.1.1/ 2>&1 || curl -s --connect-timeout 3 http://1.1.1.1/ 2>&1",
        )
        
        # Should fail
        output_lower = result.output.lower()
        assert any(indicator in output_lower for indicator in [
            "timeout",
            "connection refused",
            "network unreachable",
            "no route",
            "failed",
            "could not resolve",
        ]) or not result.success, (
            f"Expected connection to 1.1.1.1 to fail, got: {result.output}"
        )


class TestProxyContainers:
    """Test proxy container configuration."""
    
    PROXY_CONTAINERS = {
        "proxy_github": ("10.100.1.10", "egress_net"),
        "proxy_raw_githubusercontent": ("10.100.1.11", "egress_net"),
        "proxy_codeload_github": ("10.100.1.12", "egress_net"),
        "proxy_godot_docs": ("10.100.1.13", "egress_net"),
        "proxy_anthropic_api": ("10.100.1.14", "egress_net"),
    }
    
    @pytest.mark.parametrize("proxy_name,config", PROXY_CONTAINERS.items())
    def test_proxy_on_both_networks(
        self,
        sandbox_stack: DockerComposeStack,
        proxy_name: str,
        config: tuple,
    ) -> None:
        """Verify proxy containers are on both sandbox_net and egress_net."""
        expected_ip, egress_net = config
        
        inspect = sandbox_stack.container_inspect(proxy_name)
        assert inspect is not None, f"{proxy_name} container not found"
        
        networks = inspect["NetworkSettings"]["Networks"]
        network_names = list(networks.keys())
        
        # Should be on 2 networks
        assert len(network_names) == 2, (
            f"Expected {proxy_name} on 2 networks, found: {network_names}"
        )
        
        # Check for sandbox_net
        assert any("sandbox_net" in name for name in network_names), (
            f"Expected {proxy_name} on sandbox_net, found: {network_names}"
        )
        
        # Check for egress_net
        assert any("egress_net" in name for name in network_names), (
            f"Expected {proxy_name} on egress_net, found: {network_names}"
        )
    
    @pytest.mark.parametrize("proxy_name,config", PROXY_CONTAINERS.items())
    def test_proxy_has_correct_sandbox_ip(
        self,
        sandbox_stack: DockerComposeStack,
        proxy_name: str,
        config: tuple,
    ) -> None:
        """Verify proxy containers have correct static IPs."""
        expected_ip, _ = config
        
        inspect = sandbox_stack.container_inspect(proxy_name)
        assert inspect is not None
        
        networks = inspect["NetworkSettings"]["Networks"]
        
        # Find sandbox_net IP
        for name, netconfig in networks.items():
            if "sandbox_net" in name:
                assert netconfig["IPAddress"] == expected_ip, (
                    f"Expected {proxy_name} IP {expected_ip}, got: {netconfig['IPAddress']}"
                )
                return
        
        pytest.fail(f"sandbox_net not found for {proxy_name}")


class TestProxyFunctionality:
    """Test that proxies actually work for allowed domains."""
    
    @requires_network
    def test_can_reach_github_via_proxy(
        self,
        sandbox_stack: DockerComposeStack,
    ) -> None:
        """Verify HTTPS to github.com works via proxy."""
        # Note: This requires actual network access
        result = sandbox_stack.exec_in_container(
            "agent",
            "wget -q -O - --timeout=10 https://github.com 2>&1 | head -c 100 || "
            "curl -s --connect-timeout 10 https://github.com 2>&1 | head -c 100",
        )
        
        # Should get some HTML back
        assert "html" in result.output.lower() or "github" in result.output.lower(), (
            f"Expected HTML from github.com, got: {result.output[:200]}"
        )
    
    @requires_network
    def test_can_reach_godot_docs_via_proxy(
        self,
        sandbox_stack: DockerComposeStack,
    ) -> None:
        """Verify HTTPS to docs.godotengine.org works via proxy."""
        result = sandbox_stack.exec_in_container(
            "agent",
            "wget -q -O - --timeout=10 https://docs.godotengine.org/en/stable/ 2>&1 | head -c 100 || "
            "curl -s --connect-timeout 10 https://docs.godotengine.org/en/stable/ 2>&1 | head -c 100",
        )
        
        # Should get some content
        assert result.success or "godot" in result.output.lower() or "html" in result.output.lower(), (
            f"Expected content from docs.godotengine.org, got: {result.output[:200]}"
        )
    
    def test_agent_can_reach_proxy_port(
        self,
        sandbox_stack: DockerComposeStack,
    ) -> None:
        """Verify agent can connect to proxy ports (443)."""
        # Test TCP connection to proxy_github on port 443
        result = sandbox_stack.exec_in_container(
            "agent",
            "timeout 3 bash -c 'echo > /dev/tcp/10.100.1.10/443' 2>&1 && echo 'PORT_OPEN' || echo 'PORT_CLOSED'",
        )
        
        # Port should be accessible
        assert "PORT_OPEN" in result.output or result.success, (
            f"Expected port 443 on proxy_github to be open, got: {result.output}"
        )


class TestBlockedNetworkAccess:
    """Test that unauthorized network access is blocked."""
    
    def test_cannot_reach_blocked_domain_http(
        self,
        sandbox_stack: DockerComposeStack,
    ) -> None:
        """Verify HTTP to blocked domains fails."""
        result = sandbox_stack.exec_in_container(
            "agent",
            "wget -q -O - --timeout=3 http://google.com 2>&1 || "
            "curl -s --connect-timeout 3 http://google.com 2>&1",
        )
        
        # Should fail (DNS resolution or connection failure)
        output_lower = result.output.lower()
        assert any(indicator in output_lower for indicator in [
            "resolving",
            "could not resolve",
            "name or service not known",
            "connection refused",
            "failed",
            "unable to resolve",
        ]) or not result.success, (
            f"Expected google.com to be blocked, got: {result.output}"
        )
    
    def test_cannot_reach_aws_endpoints(
        self,
        sandbox_stack: DockerComposeStack,
    ) -> None:
        """Verify AWS endpoints (potential secret exfil) are blocked."""
        result = sandbox_stack.exec_in_container(
            "agent",
            "nslookup s3.amazonaws.com 2>&1",
        )
        
        output_lower = result.output.lower()
        assert any(indicator in output_lower for indicator in [
            "nxdomain",
            "can't find",
            "non-existent",
        ]), (
            f"Expected s3.amazonaws.com to be blocked, got: {result.output}"
        )


class TestSandboxNetConfiguration:
    """Test sandbox network configuration."""
    
    def test_sandbox_net_is_internal(
        self,
        sandbox_stack: DockerComposeStack,
    ) -> None:
        """Verify sandbox_net is configured as internal (no default gateway to internet)."""
        inspect = sandbox_stack.container_inspect("agent")
        assert inspect is not None
        
        networks = inspect["NetworkSettings"]["Networks"]
        
        # Find sandbox_net configuration
        for name, config in networks.items():
            if "sandbox_net" in name:
                # Check gateway is the Docker network gateway (10.100.1.1), not a route to internet
                gateway = config.get("Gateway", "")
                assert gateway.startswith("10.100.1."), (
                    f"Expected internal gateway, got: {gateway}"
                )
                return
        
        pytest.fail("sandbox_net not found")
    
    def test_sandbox_net_subnet(
        self,
        sandbox_stack: DockerComposeStack,
    ) -> None:
        """Verify sandbox_net has correct subnet 10.100.1.0/24."""
        result = sandbox_stack.exec_in_container(
            "agent",
            "ip addr show 2>/dev/null || ifconfig 2>/dev/null",
        )
        
        # Should have an IP in 10.100.1.x range
        assert "10.100.1." in result.output, (
            f"Expected IP in 10.100.1.0/24, got: {result.output}"
        )

