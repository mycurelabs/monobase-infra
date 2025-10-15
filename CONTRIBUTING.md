# Contributing to Monobase Infrastructure

Thank you for your interest in contributing to the Monobase Infrastructure project! This document provides guidelines for contributing.

## Table of Contents

1. [Code of Conduct](#code-of-conduct)
2. [Getting Started](#getting-started)
3. [Development Workflow](#development-workflow)
4. [Coding Standards](#coding-standards)
5. [Testing Requirements](#testing-requirements)
6. [Pull Request Process](#pull-request-process)
7. [Documentation](#documentation)

## Code of Conduct

- Be respectful and inclusive
- Focus on constructive feedback
- Help maintain a welcoming environment
- Report unacceptable behavior to the maintainers

## Getting Started

### Prerequisites

- **[mise](https://mise.jdx.dev)** - Manages all development tool versions (terraform, kubectl, helm, linters, etc.)
- **Docker** - For local testing with k3d

All other tools (terraform, kubectl, helm, tflint, yamllint, shellcheck, markdownlint, just) are automatically installed by mise.

### Local Development Setup

1. **Fork and clone the repository**
   ```bash
   git clone https://github.com/YOUR-USERNAME/monobase-infra.git
   cd monobase-infra
   ```

2. **Install mise** (one-time setup)
   ```bash
   # macOS/Linux
   curl https://mise.run | sh
   
   # Or via package manager
   brew install mise        # macOS
   apt install mise         # Ubuntu/Debian
   dnf install mise         # Fedora
   pacman -S mise           # Arch Linux
   
   # Activate mise in your shell (add to ~/.bashrc or ~/.zshrc)
   echo 'eval "$(mise activate bash)"' >> ~/.bashrc   # bash
   echo 'eval "$(mise activate zsh)"' >> ~/.zshrc    # zsh
   source ~/.bashrc  # or source ~/.zshrc
   ```

3. **Install all development tools** (one command!)
   ```bash
   mise install  # Reads .tool-versions and installs everything
   ```

4. **Create a k3d cluster for testing** (optional)
   ```bash
   k3d cluster create monobase-dev --agents 2
   ```

5. **Start developing!**
   ```bash
   mise run check  # Run all linters and validation
   mise run fmt    # Format code
   mise tasks      # List all available tasks
   ```

## Development Workflow

### Branching Strategy

- `main` - Production-ready code
- `develop` - Integration branch for features
- `feature/your-feature-name` - Feature branches
- `fix/issue-description` - Bug fix branches

### Making Changes

1. **Create a feature branch**
   ```bash
   git checkout -b feature/my-new-feature
   ```

2. **Make your changes**
   - Follow coding standards (see below)
   - Add tests if applicable
   - Update documentation

3. **Format and validate**
   ```bash
   mise run fmt      # Format all code
   mise run check    # Run all linters and validation
   ```

4. **Commit your changes**
   ```bash
   git add .
   git commit -m "feat: add new feature"
   ```

### Commit Message Format

Follow [Conventional Commits](https://www.conventionalcommits.org/):

```
<type>(<scope>): <subject>

<body>

<footer>
```

**Types:**
- `feat`: New feature
- `fix`: Bug fix
- `docs`: Documentation changes
- `style`: Code style changes (formatting, no logic change)
- `refactor`: Code refactoring
- `test`: Adding or updating tests
- `chore`: Maintenance tasks

**Examples:**
```
feat(helm): add Valkey caching support

Add optional Valkey deployment for caching layer.
Includes replicaset configuration and metrics.

Closes #123
```

## Coding Standards

### Terraform/OpenTofu

- Use descriptive resource names
- Add comments for complex logic
- Pin provider versions
- Use variables for configurable values
- Include validation blocks for inputs
- Add outputs for important values

**Example:**
```hcl
variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.cluster_name))
    error_message = "Cluster name must be lowercase alphanumeric with hyphens"
  }
}
```

### Helm Charts

- Follow [Helm best practices](https://helm.sh/docs/chart_best_practices/)
- Use semantic versioning for chart versions
- Document all values in values.yaml with comments
- Include NOTES.txt for post-install instructions
- Add helpers in _helpers.tpl for reusable templates

### Shell Scripts

- Use `#!/bin/bash` shebang
- Add `set -e` for error handling
- Include usage function
- Use color codes for output (RED, GREEN, YELLOW)
- Add comments for complex operations

### YAML Files

- Use 2-space indentation
- Keep lines under 120 characters
- Add comments for complex configurations
- Follow yamllint rules

## Testing Requirements

### Before Submitting PR

1. **Run all checks**
   ```bash
   mise run check        # Run all linters and validation
   mise run test-helm    # Run Helm unit tests
   ```

2. **Individual validation** (optional)
   ```bash
   mise run validate-tf    # Validate Terraform modules
   mise run validate-helm  # Validate Helm charts
   mise run lint-tf        # Lint Terraform with tflint
   mise run lint-helm      # Lint Helm charts
   ```

3. **Available mise tasks**
   ```bash
   mise tasks        # Show all available tasks
   mise run fmt      # Format all code
   mise run lint     # Run all linters
   mise run validate # Validate syntax
   mise run fix      # Auto-fix issues
   mise run secrets  # Scan for secrets
   ```

4. **Run integration tests (if applicable)**
   ```bash
   # Creates k3d cluster and deploys full stack
   .github/workflows/integration.yml
   ```

### Adding Tests

- Add Helm unit tests in `charts/*/tests/`
- Add integration test scenarios
- Document test procedures

## Pull Request Process

### Creating a PR

1. **Push your branch**
   ```bash
   git push origin feature/my-feature
   ```

2. **Create pull request on GitHub**
   - Use a clear, descriptive title
   - Fill out the PR template completely
   - Link related issues
   - Add screenshots for UI changes

3. **PR Checklist**
   - [ ] Code follows project coding standards
   - [ ] Tests pass locally
   - [ ] Documentation updated
   - [ ] CHANGELOG.md updated (for user-facing changes)
   - [ ] Commit messages follow conventional commits format
   - [ ] No merge conflicts with main branch

### Review Process

- PRs require at least one approval
- Address all review comments
- Keep PR focused on a single concern
- Squash commits before merging (if requested)

### After Approval

- Maintainers will merge your PR
- Your changes will be included in the next release
- Delete your feature branch after merge

## Documentation

### What to Document

- New features and their usage
- Configuration changes
- Breaking changes
- Migration guides (for breaking changes)
- Architecture decisions

### Documentation Standards

- Use clear, concise language
- Include code examples
- Add diagrams for complex concepts (use Mermaid)
- Keep docs in sync with code changes
- Update CHANGELOG.md for user-facing changes

### Where to Add Documentation

- `README.md` - Overview and quick start
- `docs/` - Detailed documentation
- `CHANGELOG.md` - User-facing changes
- Inline comments - Complex code logic
- Helm chart NOTES.txt - Post-install instructions

## Questions?

- Open an issue for questions
- Tag maintainers for urgent matters
- Check existing issues and PRs first

## License

By contributing, you agree that your contributions will be licensed under the same license as the project.

---

**Thank you for contributing to Monobase Infrastructure!**
