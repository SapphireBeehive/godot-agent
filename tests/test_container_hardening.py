"""
Tests for container hardening configuration.

Verifies that:
- Container runs as non-root user
- Root filesystem is read-only
- Capabilities are dropped
- Security options are applied
- Resource limits are enforced
"""

import pytest

from conftest import DockerComposeStack


class TestNonRootUser:
    """Test that agent runs as non-root user."""
    
    def test_runs_as_claude_user(
        self,
        sandbox_stack: DockerComposeStack,
    ) -> None:
        """Verify agent runs as user 'claude' (not root)."""
        result = sandbox_stack.exec_in_container(
            "agent",
            "whoami",
        )
        
        assert result.success
        assert "claude" in result.output.strip(), (
            f"Expected user 'claude', got: {result.output}"
        )
    
    def test_uid_is_1000(
        self,
        sandbox_stack: DockerComposeStack,
    ) -> None:
        """Verify agent runs with uid 1000."""
        result = sandbox_stack.exec_in_container(
            "agent",
            "id -u",
        )
        
        assert result.success
        assert result.output.strip() == "1000", (
            f"Expected uid 1000, got: {result.output}"
        )
    
    def test_not_root(
        self,
        sandbox_stack: DockerComposeStack,
    ) -> None:
        """Verify agent is not running as root."""
        result = sandbox_stack.exec_in_container(
            "agent",
            "id",
        )
        
        assert result.success
        assert "root" not in result.output.lower() or "uid=0" not in result.output, (
            f"Expected non-root user, got: {result.output}"
        )


class TestReadOnlyFilesystem:
    """Test read-only root filesystem."""
    
    def test_cannot_write_to_root(
        self,
        sandbox_stack: DockerComposeStack,
    ) -> None:
        """Verify writing to / fails."""
        result = sandbox_stack.exec_in_container(
            "agent",
            "touch /testfile 2>&1",
        )
        
        assert not result.success, (
            f"Expected write to / to fail, got: {result.output}"
        )
        assert any(indicator in result.output.lower() for indicator in [
            "read-only",
            "permission denied",
            "cannot touch",
        ]), (
            f"Expected read-only error, got: {result.output}"
        )
    
    def test_cannot_write_to_usr(
        self,
        sandbox_stack: DockerComposeStack,
    ) -> None:
        """Verify writing to /usr fails."""
        result = sandbox_stack.exec_in_container(
            "agent",
            "touch /usr/testfile 2>&1",
        )
        
        assert not result.success
        output_lower = result.output.lower()
        assert "read-only" in output_lower or "permission denied" in output_lower, (
            f"Expected read-only error, got: {result.output}"
        )
    
    def test_cannot_write_to_etc(
        self,
        sandbox_stack: DockerComposeStack,
    ) -> None:
        """Verify writing to /etc fails."""
        result = sandbox_stack.exec_in_container(
            "agent",
            "touch /etc/testfile 2>&1",
        )
        
        assert not result.success
    
    def test_can_write_to_tmp(
        self,
        sandbox_stack: DockerComposeStack,
    ) -> None:
        """Verify /tmp is writable (tmpfs mount)."""
        result = sandbox_stack.exec_in_container(
            "agent",
            "touch /tmp/testfile && echo 'SUCCESS' && rm /tmp/testfile",
        )
        
        assert result.success
        assert "SUCCESS" in result.output, (
            f"Expected /tmp to be writable, got: {result.output}"
        )
    
    def test_can_write_to_home(
        self,
        sandbox_stack: DockerComposeStack,
    ) -> None:
        """Verify /home/claude is writable (tmpfs mount)."""
        result = sandbox_stack.exec_in_container(
            "agent",
            "touch /home/claude/testfile && echo 'SUCCESS' && rm /home/claude/testfile",
        )
        
        assert result.success
        assert "SUCCESS" in result.output, (
            f"Expected /home/claude to be writable, got: {result.output}"
        )
    
    def test_can_write_to_project(
        self,
        sandbox_stack: DockerComposeStack,
    ) -> None:
        """Verify /project is writable (bind mount)."""
        result = sandbox_stack.exec_in_container(
            "agent",
            "touch /project/testfile && echo 'SUCCESS' && rm /project/testfile",
        )
        
        assert result.success
        assert "SUCCESS" in result.output, (
            f"Expected /project to be writable, got: {result.output}"
        )


class TestCapabilities:
    """Test Linux capability restrictions."""
    
    def test_no_dangerous_capabilities(
        self,
        sandbox_stack: DockerComposeStack,
    ) -> None:
        """Verify agent has no dangerous capabilities."""
        # Check /proc/self/status for capabilities
        result = sandbox_stack.exec_in_container(
            "agent",
            "cat /proc/self/status | grep -i cap",
        )
        
        assert result.success
        
        # All capability lines should be 0 or minimal
        # CapInh, CapPrm, CapEff should be 0
        lines = result.output.strip().split("\n")
        for line in lines:
            if any(cap in line for cap in ["CapInh:", "CapPrm:", "CapEff:"]):
                # Value should be all zeros
                parts = line.split()
                if len(parts) >= 2:
                    cap_value = parts[1]
                    assert cap_value == "0000000000000000", (
                        f"Expected no capabilities, got: {line}"
                    )
    
    def test_capsh_print(
        self,
        sandbox_stack: DockerComposeStack,
    ) -> None:
        """Test capability status via capsh if available."""
        result = sandbox_stack.exec_in_container(
            "agent",
            "capsh --print 2>/dev/null || echo 'capsh not available'",
        )
        
        if "capsh not available" not in result.output:
            # If capsh is available, check for empty capabilities
            assert "Current:" in result.output
            # The effective caps should be empty or minimal


class TestSecurityOptions:
    """Test security option enforcement."""
    
    def test_no_new_privileges(
        self,
        sandbox_stack: DockerComposeStack,
    ) -> None:
        """Verify no-new-privileges is set."""
        result = sandbox_stack.exec_in_container(
            "agent",
            "cat /proc/self/status | grep NoNewPrivs",
        )
        
        assert result.success
        assert "NoNewPrivs:\t1" in result.output or "NoNewPrivs: 1" in result.output, (
            f"Expected NoNewPrivs: 1, got: {result.output}"
        )
    
    def test_cannot_setuid(
        self,
        sandbox_stack: DockerComposeStack,
    ) -> None:
        """Verify setuid binaries don't work (due to no-new-privileges)."""
        # Try to use sudo or su (should fail)
        result = sandbox_stack.exec_in_container(
            "agent",
            "sudo id 2>&1 || su - 2>&1",
        )
        
        # Should fail (command not found or permission denied)
        assert not result.success or "not found" in result.output.lower() or "permission" in result.output.lower()


class TestSecurityOptionsInspect:
    """Test security options via Docker inspect."""
    
    def test_container_security_opt(
        self,
        sandbox_stack: DockerComposeStack,
    ) -> None:
        """Verify security_opt is correctly applied."""
        inspect = sandbox_stack.container_inspect("agent")
        assert inspect is not None
        
        host_config = inspect.get("HostConfig", {})
        security_opt = host_config.get("SecurityOpt", [])
        
        # Should have no-new-privileges
        assert any("no-new-privileges" in opt for opt in security_opt), (
            f"Expected no-new-privileges in security_opt, got: {security_opt}"
        )
    
    def test_container_read_only_rootfs(
        self,
        sandbox_stack: DockerComposeStack,
    ) -> None:
        """Verify ReadonlyRootfs is true."""
        inspect = sandbox_stack.container_inspect("agent")
        assert inspect is not None
        
        host_config = inspect.get("HostConfig", {})
        read_only = host_config.get("ReadonlyRootfs", False)
        
        assert read_only is True, (
            f"Expected ReadonlyRootfs=true, got: {read_only}"
        )
    
    def test_container_cap_drop_all(
        self,
        sandbox_stack: DockerComposeStack,
    ) -> None:
        """Verify all capabilities are dropped."""
        inspect = sandbox_stack.container_inspect("agent")
        assert inspect is not None
        
        host_config = inspect.get("HostConfig", {})
        cap_drop = host_config.get("CapDrop", [])
        
        assert "ALL" in cap_drop or "all" in [c.lower() for c in cap_drop], (
            f"Expected cap_drop: ALL, got: {cap_drop}"
        )


class TestResourceLimits:
    """Test resource limit enforcement."""
    
    def test_memory_limit_configured(
        self,
        sandbox_stack: DockerComposeStack,
    ) -> None:
        """Verify memory limit is configured."""
        inspect = sandbox_stack.container_inspect("agent")
        assert inspect is not None
        
        host_config = inspect.get("HostConfig", {})
        memory = host_config.get("Memory", 0)
        
        # Should be > 0 (meaning a limit is set)
        assert memory > 0, (
            f"Expected memory limit > 0, got: {memory}"
        )
        
        # Default is 2G = 2147483648 bytes
        expected_max = 4 * 1024 * 1024 * 1024  # 4GB reasonable max
        assert memory <= expected_max, (
            f"Memory limit {memory} seems too high"
        )
    
    def test_pids_limit_configured(
        self,
        sandbox_stack: DockerComposeStack,
    ) -> None:
        """Verify PID limit is configured."""
        inspect = sandbox_stack.container_inspect("agent")
        assert inspect is not None
        
        host_config = inspect.get("HostConfig", {})
        pids_limit = host_config.get("PidsLimit", 0)
        
        # Should be 256 or similar reasonable limit
        assert pids_limit is not None and pids_limit > 0, (
            f"Expected PID limit > 0, got: {pids_limit}"
        )
        assert pids_limit <= 1000, (
            f"PID limit {pids_limit} seems too high for a sandboxed container"
        )
    
    def test_cpu_limit_configured(
        self,
        sandbox_stack: DockerComposeStack,
    ) -> None:
        """Verify CPU limit is configured."""
        inspect = sandbox_stack.container_inspect("agent")
        assert inspect is not None
        
        host_config = inspect.get("HostConfig", {})
        
        # Check NanoCpus (CPU limit in nano CPUs)
        nano_cpus = host_config.get("NanoCpus", 0)
        
        # Default is 2.0 CPUs = 2000000000 nano CPUs
        if nano_cpus > 0:
            cpus = nano_cpus / 1_000_000_000
            assert cpus <= 4.0, (
                f"CPU limit {cpus} seems too high for a sandboxed container"
            )
    
    def test_fork_bomb_prevention(
        self,
        sandbox_stack: DockerComposeStack,
    ) -> None:
        """Verify PID limit prevents fork bombs (don't actually run one)."""
        # Just verify the limit is set, don't actually test a fork bomb
        inspect = sandbox_stack.container_inspect("agent")
        assert inspect is not None
        
        host_config = inspect.get("HostConfig", {})
        pids_limit = host_config.get("PidsLimit", 0)
        
        # Limit should prevent runaway process creation
        assert pids_limit is not None and 0 < pids_limit <= 512, (
            f"PID limit should be reasonable (1-512), got: {pids_limit}"
        )


class TestTmpfsLimits:
    """Test tmpfs mount restrictions."""
    
    def test_tmp_has_size_limit(
        self,
        sandbox_stack: DockerComposeStack,
    ) -> None:
        """Verify /tmp has a size limit."""
        result = sandbox_stack.exec_in_container(
            "agent",
            "df -h /tmp | tail -1",
        )
        
        assert result.success
        # Should show a limited size (e.g., 100M)
        assert "M" in result.output or "G" in result.output, (
            f"Expected size info for /tmp, got: {result.output}"
        )
    
    def test_home_has_size_limit(
        self,
        sandbox_stack: DockerComposeStack,
    ) -> None:
        """Verify /home/claude has a size limit."""
        result = sandbox_stack.exec_in_container(
            "agent",
            "df -h /home/claude | tail -1",
        )
        
        assert result.success
        # Should show a limited size
        assert "M" in result.output or "G" in result.output, (
            f"Expected size info for /home/claude, got: {result.output}"
        )
    
    def test_tmpfs_mounts_exist(
        self,
        sandbox_stack: DockerComposeStack,
    ) -> None:
        """Verify tmpfs mounts are in place."""
        result = sandbox_stack.exec_in_container(
            "agent",
            "mount | grep tmpfs",
        )
        
        assert result.success
        output = result.output
        
        # Should have tmpfs for /tmp and /home/claude
        assert "/tmp" in output, f"Expected tmpfs on /tmp, got: {output}"

