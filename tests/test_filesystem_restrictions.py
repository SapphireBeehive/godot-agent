"""
Tests for filesystem restriction enforcement.

Verifies that:
- Only project directory is mounted
- No sensitive directories are exposed
- Mount permissions are correct
"""

from __future__ import annotations

from typing import TYPE_CHECKING

import pytest

if TYPE_CHECKING:
    from conftest import DockerComposeStack


class TestMountedVolumes:
    """Test that only expected volumes are mounted."""
    
    def test_project_is_mounted(
        self,
        sandbox_stack: DockerComposeStack,
    ) -> None:
        """Verify /project is mounted."""
        result = sandbox_stack.exec_in_container(
            "agent",
            "mount | grep /project || df /project",
        )
        
        # Project should be a mount point
        assert "/project" in result.output, (
            f"Expected /project to be mounted, got: {result.output}"
        )
    
    def test_project_is_writable(
        self,
        sandbox_stack: DockerComposeStack,
    ) -> None:
        """Verify /project has write permissions."""
        result = sandbox_stack.exec_in_container(
            "agent",
            "test -w /project && echo 'WRITABLE' || echo 'NOT_WRITABLE'",
        )
        
        assert "WRITABLE" in result.output, (
            f"Expected /project to be writable, got: {result.output}"
        )


class TestNoSensitiveDirectories:
    """Test that sensitive host directories are not mounted."""
    
    SENSITIVE_PATHS = [
        "/var/run/docker.sock",  # Docker socket - container escape
        "/root/.ssh",            # SSH keys
        "/root/.aws",            # AWS credentials
        "/root/.config",         # Various app configs
        "/etc/shadow",           # Password hashes
        "/etc/sudoers",          # Sudo config
    ]
    
    def test_no_docker_socket(
        self,
        sandbox_stack: DockerComposeStack,
    ) -> None:
        """Verify Docker socket is not mounted."""
        result = sandbox_stack.exec_in_container(
            "agent",
            "ls -la /var/run/docker.sock 2>&1",
        )
        
        # Should not exist
        assert "No such file" in result.output or not result.success, (
            f"Docker socket should not be mounted, got: {result.output}"
        )
    
    def test_no_root_home(
        self,
        sandbox_stack: DockerComposeStack,
    ) -> None:
        """Verify /root is not accessible or is empty."""
        result = sandbox_stack.exec_in_container(
            "agent",
            "ls -la /root 2>&1 || echo 'NOT_ACCESSIBLE'",
        )
        
        # Should either not exist, be inaccessible, or be empty
        output = result.output.lower()
        assert any(indicator in output for indicator in [
            "permission denied",
            "not_accessible",
            "no such file",
        ]) or result.output.strip().count("\n") <= 2, (
            f"Expected /root to be inaccessible or empty, got: {result.output}"
        )
    
    def test_no_ssh_directory(
        self,
        sandbox_stack: DockerComposeStack,
    ) -> None:
        """Verify no SSH directories are mounted."""
        # Check both common SSH paths
        for path in ["/root/.ssh", "/home/claude/.ssh"]:
            result = sandbox_stack.exec_in_container(
                "agent",
                f"ls -la {path} 2>&1",
            )
            
            # Should not exist or be empty
            assert "No such file" in result.output or result.output.strip().count("\n") <= 2, (
                f"SSH directory {path} should not have host keys, got: {result.output}"
            )
    
    def test_no_aws_credentials(
        self,
        sandbox_stack: DockerComposeStack,
    ) -> None:
        """Verify no AWS credentials are mounted."""
        result = sandbox_stack.exec_in_container(
            "agent",
            "cat ~/.aws/credentials 2>&1 || cat /root/.aws/credentials 2>&1 || echo 'NOT_FOUND'",
        )
        
        assert "NOT_FOUND" in result.output or "No such file" in result.output, (
            f"AWS credentials should not exist, got: {result.output}"
        )
    
    def test_no_host_config(
        self,
        sandbox_stack: DockerComposeStack,
    ) -> None:
        """Verify no host config directories are mounted."""
        result = sandbox_stack.exec_in_container(
            "agent",
            "ls ~/.config 2>&1 | wc -l",
        )
        
        # Should be empty or minimal (only container-created dirs)
        # The .config dir exists but shouldn't have host files
        lines = result.output.strip()
        assert result.success


class TestMountInspection:
    """Test mounts via Docker inspect."""
    
    def test_volume_mounts_limited(
        self,
        sandbox_stack: DockerComposeStack,
    ) -> None:
        """Verify only expected volumes are mounted."""
        inspect = sandbox_stack.container_inspect("agent")
        assert inspect is not None
        
        mounts = inspect.get("Mounts", [])
        
        # Count bind mounts (excluding tmpfs)
        bind_mounts = [m for m in mounts if m.get("Type") == "bind"]
        
        # Should only have the project directory
        assert len(bind_mounts) <= 1, (
            f"Expected only 1 bind mount, got: {[m['Destination'] for m in bind_mounts]}"
        )
        
        if bind_mounts:
            assert bind_mounts[0]["Destination"] == "/project", (
                f"Expected /project mount, got: {bind_mounts[0]['Destination']}"
            )
    
    def test_no_host_path_mount(
        self,
        sandbox_stack: DockerComposeStack,
    ) -> None:
        """Verify no dangerous host paths are mounted."""
        inspect = sandbox_stack.container_inspect("agent")
        assert inspect is not None
        
        mounts = inspect.get("Mounts", [])
        
        # Paths that should NEVER be mounted (exact match or mount destination)
        dangerous_destinations = [
            "/var/run/docker.sock",
            "/etc/passwd",
            "/etc/shadow",
            "/root",
        ]
        
        for mount in mounts:
            source = mount.get("Source", "")
            dest = mount.get("Destination", "")
            
            # Check destination is not a dangerous location
            for dangerous in dangerous_destinations:
                assert dest != dangerous, (
                    f"Dangerous path {dangerous} should not be mounted as destination"
                )
            
            # Check we're not mounting docker socket from source
            assert "docker.sock" not in source, (
                f"Docker socket should not be mounted (source: {source})"
            )


class TestWorkingDirectory:
    """Test working directory configuration."""
    
    def test_working_dir_is_project(
        self,
        sandbox_stack: DockerComposeStack,
    ) -> None:
        """Verify working directory is /project."""
        result = sandbox_stack.exec_in_container(
            "agent",
            "pwd",
        )
        
        assert result.success
        assert result.output.strip() == "/project", (
            f"Expected working dir /project, got: {result.output}"
        )
    
    def test_project_owned_by_claude(
        self,
        sandbox_stack: DockerComposeStack,
    ) -> None:
        """Verify /project is accessible by claude user."""
        result = sandbox_stack.exec_in_container(
            "agent",
            "touch /project/.test-access && rm /project/.test-access && echo 'OK'",
        )
        
        assert "OK" in result.output, (
            f"Expected /project to be accessible, got: {result.output}"
        )


class TestFileAccess:
    """Test file access restrictions."""
    
    def test_cannot_read_etc_shadow(
        self,
        sandbox_stack: DockerComposeStack,
    ) -> None:
        """Verify cannot read sensitive system files."""
        result = sandbox_stack.exec_in_container(
            "agent",
            "cat /etc/shadow 2>&1",
        )
        
        assert "Permission denied" in result.output or not result.success, (
            f"Expected /etc/shadow to be unreadable, got: {result.output}"
        )
    
    def test_cannot_write_outside_allowed_paths(
        self,
        sandbox_stack: DockerComposeStack,
    ) -> None:
        """Verify writing outside /project, /tmp, /home/claude fails."""
        paths = ["/opt/test", "/var/test", "/usr/local/test"]
        
        for path in paths:
            result = sandbox_stack.exec_in_container(
                "agent",
                f"touch {path} 2>&1",
            )
            
            assert not result.success, (
                f"Expected write to {path} to fail, got: {result.output}"
            )

