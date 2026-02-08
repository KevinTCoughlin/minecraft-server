# Contributing to Minecraft Server

Thank you for your interest in contributing! This guide will help you get started.

## Table of Contents

- [Code of Conduct](#code-of-conduct)
- [Getting Started](#getting-started)
- [Development Setup](#development-setup)
- [Making Changes](#making-changes)
- [Testing](#testing)
- [Submitting Changes](#submitting-changes)
- [Style Guidelines](#style-guidelines)

## Code of Conduct

This project follows the [Contributor Covenant Code of Conduct](https://www.contributor-covenant.org/version/2/1/code_of_conduct/). By participating, you are expected to uphold this code.

## Getting Started

1. **Fork the repository** on GitHub
2. **Clone your fork** locally:
   ```bash
   git clone https://github.com/YOUR_USERNAME/minecraft-server.git
   cd minecraft-server
   ```
3. **Add upstream remote**:
   ```bash
   git remote add upstream https://github.com/KevinTCoughlin/minecraft-server.git
   ```

## Development Setup

### Prerequisites

- **Java 21+** (Eclipse Temurin recommended)
- **Gradle 8.x** (wrapper included)
- **Git**

### Install Eclipse Temurin

We recommend Eclipse Temurin (Eclipse Foundation's OpenJDK distribution):

- **macOS**: `brew install --cask temurin21`
- **Linux**: Follow [Adoptium installation guide](https://adoptium.net/installation/linux/)
- **Windows**: Download from [Adoptium.net](https://adoptium.net/)

### Initial Setup

```bash
# Build all plugins
./gradlew build

# Run tests
./gradlew test

# Set up server
./setup.sh
```

### Using Dev Container

We provide a VS Code dev container with all tools pre-configured:

1. Install [Docker](https://www.docker.com/products/docker-desktop) and [VS Code](https://code.visualstudio.com/)
2. Install the [Dev Containers extension](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-containers)
3. Open the project in VS Code
4. When prompted, click "Reopen in Container"

## Making Changes

### Creating a Branch

```bash
# Sync with upstream
git fetch upstream
git checkout main
git merge upstream/main

# Create a feature branch
git checkout -b feature/my-new-feature
```

### Development Workflow

1. **Make your changes** in your feature branch
2. **Build and test** frequently:
   ```bash
   ./gradlew build
   ./gradlew test
   ```
3. **Test locally** with the server:
   ```bash
   ./gradlew :plugins:my-plugin:deployToServer
   ./scripts/start.sh
   ```

### Plugin Development

When creating a new plugin:

1. Create directory: `plugins/my-plugin/`
2. Add to `settings.gradle.kts`:
   ```kotlin
   include("plugins:my-plugin")
   ```
3. Create `build.gradle.kts` (copy from example-plugin)
4. Create main class extending `JavaPlugin`
5. Create `src/main/resources/plugin.yml`

See the [Plugin Development section](README.md#plugin-development) in README for details.

## Testing

### Running Tests

```bash
# Run all tests
./gradlew test

# Run tests for specific plugin
./gradlew :plugins:blackjack-plugin:test

# Run with coverage
./gradlew test jacocoTestReport
```

### Manual Testing

1. Build your plugin
2. Deploy to local server
3. Start the server
4. Test in-game

```bash
./gradlew :plugins:my-plugin:deployToServer
./scripts/start.sh
```

## Submitting Changes

### Before Submitting

- [ ] Code builds successfully
- [ ] All tests pass
- [ ] New code has tests
- [ ] Code follows style guidelines
- [ ] Documentation updated (if needed)
- [ ] Commit messages are clear

### Pull Request Process

1. **Push your changes**:
   ```bash
   git push origin feature/my-new-feature
   ```

2. **Create a Pull Request** on GitHub with:
   - Clear title describing the change
   - Description of what changed and why
   - Link to any related issues
   - Screenshots (if UI changes)

3. **Address review feedback** if requested

4. **Squash and merge** when approved

### Commit Messages

Write clear, concise commit messages:

```
Add blackjack insurance bet feature

- Implement insurance logic when dealer shows Ace
- Add insurance command handling
- Update stats tracking for insurance bets
```

## Style Guidelines

### Java/Kotlin Code

- Use **Java 21** features where appropriate
- Follow **Kotlin coding conventions** for Kotlin code
- Use **meaningful variable names**
- Add **comments for complex logic**
- Keep methods **short and focused**

### Code Formatting

The project uses automatic formatting:
- IntelliJ IDEA: Code → Reformat Code
- VS Code: Format Document (Shift+Alt+F)

### Documentation

- Update README.md for user-facing changes
- Add JavaDoc/KDoc for public APIs
- Update docs/ for major features
- Include usage examples

### Configuration Files

- Use consistent indentation (2 spaces for YAML, 4 for Gradle)
- Comment non-obvious settings
- Test configuration changes thoroughly

## Additional Resources

- [PaperMC Documentation](https://docs.papermc.io/)
- [PaperMC API Javadocs](https://jd.papermc.io/paper/1.21/)
- [Kotlin Language Guide](https://kotlinlang.org/docs/home.html)
- [Eclipse Temurin](https://adoptium.net/)

## Getting Help

- **Questions**: Open a [Discussion](https://github.com/KevinTCoughlin/minecraft-server/discussions)
- **Bugs**: Create an [Issue](https://github.com/KevinTCoughlin/minecraft-server/issues)
- **Documentation**: Check the [README](README.md) and [docs/](docs/)

## License

By contributing, you agree that your contributions will be licensed under the same [MIT License](LICENSE) that covers this project.

---

Thank you for contributing! 🎮
