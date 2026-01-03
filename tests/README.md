# Security Tests

This directory contains comprehensive tests for the Claude-Godot Sandbox security features.

## Overview

The tests verify:

1. **DNS Filtering** - Allowlisted domains resolve to proxy IPs, blocked domains return NXDOMAIN
2. **Network Restrictions** - Agent is isolated to sandbox_net, cannot reach internet directly
3. **Container Hardening** - Read-only filesystem, dropped capabilities, non-root user, resource limits
4. **Filesystem Restrictions** - Only project directory mounted, no sensitive paths exposed
5. **Offline Mode** - Zero network access with network_mode: none

## Prerequisites

- Docker (with Docker Compose v2)
- Python 3.10+
- The agent image built (`make build`)

## Installation

```bash
# Create virtual environment (optional but recommended)
python3 -m venv .venv
source .venv/bin/activate

# Install dependencies
pip install -r tests/requirements.txt
```

## Running Tests

### All tests

```bash
# Via Makefile (recommended)
make test-security

# Or directly with pytest
cd tests && pytest
```

### Specific test modules

```bash
# DNS filtering only
make test-dns

# Container hardening only
pytest tests/test_container_hardening.py

# Offline mode only
pytest tests/test_offline_mode.py
```

### With options

```bash
# Verbose output
pytest tests/ -v

# Stop on first failure
pytest tests/ -x

# Run in parallel (faster)
pytest tests/ -n auto

# Skip network-dependent tests
CI_NO_NETWORK=1 pytest tests/

# Skip slow tests
pytest tests/ -m "not slow"
```

## Test Structure

```
tests/
├── conftest.py              # Fixtures: DockerComposeStack, containers
├── pytest.ini               # Pytest configuration
├── requirements.txt         # Test dependencies
├── test_dns_filtering.py    # DNS allowlist/blocklist tests
├── test_network_restrictions.py  # Network isolation tests
├── test_container_hardening.py   # Security hardening tests
├── test_filesystem_restrictions.py  # Mount/volume tests
└── test_offline_mode.py     # Offline mode tests
```

## Writing New Tests

### Using the DockerComposeStack fixture

```python
def test_example(sandbox_stack: DockerComposeStack):
    # Execute command in agent container
    result = sandbox_stack.exec_in_container("agent", "whoami")
    
    assert result.success
    assert "claude" in result.output
```

### Checking container configuration

```python
def test_config(sandbox_stack: DockerComposeStack):
    # Get Docker inspect data
    inspect = sandbox_stack.container_inspect("agent")
    
    # Check security settings
    host_config = inspect["HostConfig"]
    assert host_config["ReadonlyRootfs"] is True
```

## CI Integration

Tests run automatically in GitHub Actions CI:

- On every push to main
- On every pull request

The CI workflow:
1. Builds the agent image
2. Starts the Docker Compose stack
3. Runs all security tests
4. Reports results

## Troubleshooting

### Tests failing to start

```bash
# Check Docker is running
docker info

# Clean up any leftover containers
docker compose -p security-test down -v
docker compose -p security-test-offline down -v

# Rebuild image
make build
```

### Container not found errors

```bash
# Check containers are running
docker ps -a | grep security-test

# View container logs
docker logs security-test-agent-1
```

### Timeout errors

The tests have a 120-second timeout. If containers are slow to start:

```bash
# Increase timeout
pytest tests/ --timeout=300
```

