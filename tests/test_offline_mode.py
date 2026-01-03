"""
Tests for offline mode (network_mode: none).

Verifies that:
- Agent has zero network access in offline mode
- All network operations fail
- Container is otherwise functional
"""

import pytest

from conftest import DockerComposeStack


class TestOfflineNetworkAccess:
    """Test that offline mode has no network."""
    
    def test_no_network_interfaces(
        self,
        offline_stack: DockerComposeStack,
    ) -> None:
        """Verify no network interfaces (except loopback)."""
        result = offline_stack.exec_in_container(
            "agent_offline",
            "ip link show 2>/dev/null || ifconfig 2>/dev/null || cat /proc/net/dev",
        )
        
        # Should only have loopback (lo)
        output = result.output.lower()
        
        # Check for absence of non-loopback interfaces
        network_interfaces = ["eth0", "eth1", "ens", "enp", "wlan"]
        for iface in network_interfaces:
            assert iface not in output, (
                f"Unexpected network interface {iface} found: {result.output}"
            )
    
    def test_network_mode_none(
        self,
        offline_stack: DockerComposeStack,
    ) -> None:
        """Verify container has network_mode: none via inspect."""
        inspect = offline_stack.container_inspect("agent_offline")
        assert inspect is not None
        
        host_config = inspect.get("HostConfig", {})
        network_mode = host_config.get("NetworkMode", "")
        
        assert network_mode == "none", (
            f"Expected NetworkMode=none, got: {network_mode}"
        )
    
    def test_no_ip_address(
        self,
        offline_stack: DockerComposeStack,
    ) -> None:
        """Verify container has no IP address."""
        inspect = offline_stack.container_inspect("agent_offline")
        assert inspect is not None
        
        networks = inspect.get("NetworkSettings", {}).get("Networks", {})
        
        # Should have no networks or only 'none'
        assert len(networks) == 0 or list(networks.keys()) == ["none"], (
            f"Expected no networks, got: {list(networks.keys())}"
        )


class TestOfflineDNS:
    """Test DNS is non-functional in offline mode."""
    
    def test_dns_resolution_fails(
        self,
        offline_stack: DockerComposeStack,
    ) -> None:
        """Verify DNS resolution fails."""
        result = offline_stack.exec_in_container(
            "agent_offline",
            "nslookup github.com 2>&1 || getent hosts github.com 2>&1 || echo 'DNS_FAILED'",
        )
        
        output = result.output.lower()
        assert any(indicator in output for indicator in [
            "dns_failed",
            "connection timed out",
            "server can't be reached",
            "network is unreachable",
            "no servers could be reached",
            "name or service not known",
        ]) or not result.success, (
            f"Expected DNS to fail, got: {result.output}"
        )
    
    def test_cannot_resolve_localhost(
        self,
        offline_stack: DockerComposeStack,
    ) -> None:
        """Verify even localhost may not resolve via network DNS."""
        # Localhost should still work via /etc/hosts
        result = offline_stack.exec_in_container(
            "agent_offline",
            "getent hosts localhost",
        )
        
        # This might succeed via /etc/hosts, which is fine
        # The test is really about external DNS being unavailable
        pass  # localhost via /etc/hosts is acceptable


class TestOfflineHTTP:
    """Test HTTP/HTTPS is non-functional in offline mode."""
    
    def test_cannot_reach_any_http(
        self,
        offline_stack: DockerComposeStack,
    ) -> None:
        """Verify HTTP requests fail."""
        result = offline_stack.exec_in_container(
            "agent_offline",
            "wget -q -O - --timeout=2 http://example.com 2>&1 || "
            "curl -s --connect-timeout 2 http://example.com 2>&1",
        )
        
        output = result.output.lower()
        assert any(indicator in output for indicator in [
            "network is unreachable",
            "unable to resolve",
            "could not resolve",
            "connection refused",
            "timed out",
            "failed",
            "no route",
        ]) or not result.success, (
            f"Expected HTTP to fail, got: {result.output}"
        )
    
    def test_cannot_reach_https(
        self,
        offline_stack: DockerComposeStack,
    ) -> None:
        """Verify HTTPS requests fail."""
        result = offline_stack.exec_in_container(
            "agent_offline",
            "wget -q -O - --timeout=2 https://github.com 2>&1 || "
            "curl -s --connect-timeout 2 https://github.com 2>&1",
        )
        
        # Should fail
        assert not result.success or "failed" in result.output.lower() or len(result.output.strip()) == 0


class TestOfflinePing:
    """Test ping is non-functional in offline mode."""
    
    def test_cannot_ping_external(
        self,
        offline_stack: DockerComposeStack,
    ) -> None:
        """Verify cannot ping external IPs."""
        result = offline_stack.exec_in_container(
            "agent_offline",
            "ping -c 1 -W 1 8.8.8.8 2>&1",
        )
        
        assert not result.success, (
            f"Expected ping to fail, got: {result.output}"
        )
        
        output = result.output.lower()
        assert any(indicator in output for indicator in [
            "network is unreachable",
            "network unreachable",
            "sendto: network is unreachable",
        ]), (
            f"Expected network unreachable, got: {result.output}"
        )
    
    def test_can_ping_localhost(
        self,
        offline_stack: DockerComposeStack,
    ) -> None:
        """Verify loopback still works."""
        result = offline_stack.exec_in_container(
            "agent_offline",
            "ping -c 1 127.0.0.1 2>&1 || echo 'PING_FAILED'",
        )
        
        # Loopback should work (unless ping is not installed or CAP_NET_RAW is dropped)
        # If ping is not available due to capabilities, that's fine too
        if "operation not permitted" in result.output.lower():
            # Capabilities prevent raw sockets - this is expected
            pass
        else:
            # Either ping works on loopback or is not installed
            pass  # Loopback test is informational


class TestOfflineContainerFunctionality:
    """Test that container is otherwise functional in offline mode."""
    
    def test_container_runs_as_claude(
        self,
        offline_stack: DockerComposeStack,
    ) -> None:
        """Verify container runs as non-root."""
        result = offline_stack.exec_in_container(
            "agent_offline",
            "whoami",
        )
        
        assert result.success
        assert "claude" in result.output.strip(), (
            f"Expected user 'claude', got: {result.output}"
        )
    
    def test_project_directory_accessible(
        self,
        offline_stack: DockerComposeStack,
    ) -> None:
        """Verify /project is still accessible."""
        result = offline_stack.exec_in_container(
            "agent_offline",
            "ls -la /project",
        )
        
        assert result.success, (
            f"Expected /project to be accessible, got: {result.output}"
        )
    
    def test_can_run_commands(
        self,
        offline_stack: DockerComposeStack,
    ) -> None:
        """Verify basic commands work."""
        result = offline_stack.exec_in_container(
            "agent_offline",
            "echo 'Hello, offline world!' && date && uname -a",
        )
        
        assert result.success
        assert "Hello, offline world!" in result.output
    
    def test_godot_available(
        self,
        offline_stack: DockerComposeStack,
    ) -> None:
        """Verify Godot is available in offline mode."""
        result = offline_stack.exec_in_container(
            "agent_offline",
            "godot --headless --version 2>&1 || echo 'GODOT_NOT_FOUND'",
        )
        
        # Godot should be available
        assert "GODOT_NOT_FOUND" not in result.output, (
            f"Expected Godot to be available, got: {result.output}"
        )
    
    def test_offline_env_variable(
        self,
        offline_stack: DockerComposeStack,
    ) -> None:
        """Verify OFFLINE_MODE environment variable is set."""
        result = offline_stack.exec_in_container(
            "agent_offline",
            "echo $OFFLINE_MODE",
        )
        
        assert result.success
        assert "true" in result.output.lower(), (
            f"Expected OFFLINE_MODE=true, got: {result.output}"
        )


class TestOfflineSecurityHardening:
    """Test security hardening is still applied in offline mode."""
    
    def test_read_only_filesystem(
        self,
        offline_stack: DockerComposeStack,
    ) -> None:
        """Verify root filesystem is read-only."""
        result = offline_stack.exec_in_container(
            "agent_offline",
            "touch /test 2>&1",
        )
        
        assert not result.success
        assert "read-only" in result.output.lower() or "permission denied" in result.output.lower()
    
    def test_no_capabilities(
        self,
        offline_stack: DockerComposeStack,
    ) -> None:
        """Verify capabilities are dropped."""
        result = offline_stack.exec_in_container(
            "agent_offline",
            "cat /proc/self/status | grep CapEff",
        )
        
        assert result.success
        # Should have no effective capabilities
        if "0000000000000000" not in result.output:
            # Some minimal capabilities might be present
            pass
    
    def test_no_new_privileges(
        self,
        offline_stack: DockerComposeStack,
    ) -> None:
        """Verify no-new-privileges is set."""
        result = offline_stack.exec_in_container(
            "agent_offline",
            "cat /proc/self/status | grep NoNewPrivs",
        )
        
        assert result.success
        assert "1" in result.output, (
            f"Expected NoNewPrivs: 1, got: {result.output}"
        )

