"""
Pytest fixtures for Claude-Godot Sandbox security tests.

These fixtures manage Docker Compose lifecycle and provide helpers for
executing commands inside containers and verifying security constraints.
"""

import os
import subprocess
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Generator, Optional

import docker
import pytest

# Project root directory
PROJECT_ROOT = Path(__file__).parent.parent
COMPOSE_DIR = PROJECT_ROOT / "compose"


@dataclass
class ExecResult:
    """Result from executing a command in a container."""
    
    exit_code: int
    output: str
    
    @property
    def success(self) -> bool:
        return self.exit_code == 0


class DockerComposeStack:
    """Manages a Docker Compose stack for testing."""
    
    def __init__(self, compose_files: list[str], project_name: str = "security-test"):
        self.compose_files = compose_files
        self.project_name = project_name
        self.client = docker.from_env()
    
    def _compose_cmd(self, *args: str) -> list[str]:
        """Build docker compose command with project name and files."""
        cmd = ["docker", "compose", "-p", self.project_name]
        for f in self.compose_files:
            cmd.extend(["-f", str(COMPOSE_DIR / f)])
        cmd.extend(args)
        return cmd
    
    def up(self, wait_for_healthy: bool = True, timeout: int = 60) -> None:
        """Start the compose stack."""
        # Create a dummy project directory for mounting
        project_dir = PROJECT_ROOT / "tests" / ".test-project"
        project_dir.mkdir(exist_ok=True)
        
        env = os.environ.copy()
        env["PROJECT_PATH"] = str(project_dir)
        
        # Start services
        subprocess.run(
            self._compose_cmd("up", "-d", "--wait" if wait_for_healthy else ""),
            check=True,
            env=env,
            cwd=PROJECT_ROOT,
            capture_output=True,
        )
        
        # Additional wait for services to stabilize
        if wait_for_healthy:
            time.sleep(3)
    
    def down(self, volumes: bool = True) -> None:
        """Stop and remove the compose stack."""
        args = ["down"]
        if volumes:
            args.append("-v")
        args.append("--remove-orphans")
        
        subprocess.run(
            self._compose_cmd(*args),
            check=False,  # Don't fail if already down
            capture_output=True,
        )
    
    def get_container(self, name: str) -> Optional[docker.models.containers.Container]:
        """Get a container by name."""
        full_name = f"{self.project_name}-{name}-1"
        try:
            return self.client.containers.get(full_name)
        except docker.errors.NotFound:
            # Try without project prefix
            try:
                return self.client.containers.get(name)
            except docker.errors.NotFound:
                return None
    
    def exec_in_container(
        self,
        container_name: str,
        command: str | list[str],
        user: str = None,
    ) -> ExecResult:
        """Execute a command in a container and return the result."""
        container = self.get_container(container_name)
        if container is None:
            return ExecResult(exit_code=1, output=f"Container {container_name} not found")
        
        if isinstance(command, str):
            command = ["sh", "-c", command]
        
        kwargs = {}
        if user:
            kwargs["user"] = user
        
        result = container.exec_run(command, **kwargs)
        return ExecResult(
            exit_code=result.exit_code,
            output=result.output.decode("utf-8", errors="replace"),
        )
    
    def container_inspect(self, container_name: str) -> Optional[dict]:
        """Get full container inspection data."""
        container = self.get_container(container_name)
        if container is None:
            return None
        return self.client.api.inspect_container(container.id)
    
    def get_container_logs(self, container_name: str, tail: int = 100) -> str:
        """Get logs from a container."""
        container = self.get_container(container_name)
        if container is None:
            return ""
        return container.logs(tail=tail).decode("utf-8", errors="replace")


@pytest.fixture(scope="module")
def sandbox_stack() -> Generator[DockerComposeStack, None, None]:
    """
    Fixture providing a running sandbox stack (base + direct).
    
    This starts the full sandbox including:
    - dnsfilter (CoreDNS)
    - All proxy containers
    - agent container
    
    The stack is started once per test module and torn down after.
    """
    stack = DockerComposeStack(
        compose_files=["compose.base.yml", "compose.direct.yml"],
        project_name="security-test",
    )
    
    # Ensure clean state
    stack.down()
    
    try:
        stack.up(wait_for_healthy=True, timeout=90)
        yield stack
    finally:
        stack.down()


@pytest.fixture(scope="module")
def offline_stack() -> Generator[DockerComposeStack, None, None]:
    """
    Fixture providing an offline-mode stack.
    
    This starts only the agent container with network_mode: none.
    """
    stack = DockerComposeStack(
        compose_files=["compose.offline.yml"],
        project_name="security-test-offline",
    )
    
    # Ensure clean state
    stack.down()
    
    try:
        stack.up(wait_for_healthy=False, timeout=30)
        yield stack
    finally:
        stack.down()


@pytest.fixture(scope="session")
def docker_client() -> docker.DockerClient:
    """Provide a Docker client for tests."""
    return docker.from_env()


@pytest.fixture
def temp_project_dir(tmp_path: Path) -> Path:
    """Create a temporary project directory for testing mounts."""
    project_dir = tmp_path / "test-project"
    project_dir.mkdir()
    (project_dir / "test.gd").write_text('print("Hello")')
    return project_dir


# Marker for tests that require network access (for proxy tests)
requires_network = pytest.mark.skipif(
    os.environ.get("CI_NO_NETWORK") == "1",
    reason="Network tests disabled in CI",
)

# Marker for slow tests
slow = pytest.mark.slow


def pytest_configure(config: pytest.Config) -> None:
    """Register custom markers."""
    config.addinivalue_line("markers", "slow: mark test as slow running")
    config.addinivalue_line(
        "markers",
        "requires_network: mark test as requiring network access",
    )

