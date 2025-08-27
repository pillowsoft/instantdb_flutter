# Contributing to InstantDB Flutter

Thank you for your interest in contributing to InstantDB Flutter! This document provides guidelines and information for contributors.

## Table of Contents

- [Code of Conduct](#code-of-conduct)
- [Getting Started](#getting-started)
- [Development Setup](#development-setup)
- [Contributing Guidelines](#contributing-guidelines)
- [Development Workflow](#development-workflow)
- [Testing](#testing)
- [Code Style](#code-style)
- [Submitting Changes](#submitting-changes)
- [Release Process](#release-process)

## Code of Conduct

We are committed to providing a friendly, safe, and welcoming environment for all contributors. Please read and follow our code of conduct:

- **Be respectful** and inclusive in your communications
- **Be collaborative** and help others learn and grow
- **Be patient** with questions and different skill levels
- **Be constructive** in feedback and criticism
- **Focus on what is best** for the community and the project

## Getting Started

### Prerequisites

- **Flutter SDK** `>=3.0.0`
- **Dart SDK** `^3.8.0`
- **Git** for version control
- **Just** for running development tasks (optional but recommended)
- **InstantDB Account** for testing (free at [instantdb.com](https://instantdb.com))

### Installation

1. **Fork the repository** on GitHub
2. **Clone your fork** locally:
   ```bash
   git clone https://github.com/YOUR_USERNAME/instantdb_flutter.git
   cd instantdb_flutter
   ```

3. **Set up the upstream remote**:
   ```bash
   git remote add upstream https://github.com/instantdb/instantdb_flutter.git
   ```

4. **Install dependencies**:
   ```bash
   just install  # or flutter pub get && cd example && flutter pub get
   ```

## Development Setup

### Environment Configuration

1. **Copy environment files**:
   ```bash
   cp .env.example .env
   cp example/.env.example example/.env
   ```

2. **Get your InstantDB App ID**:
   - Sign up at [instantdb.com](https://instantdb.com)
   - Create a new app in the dashboard
   - Copy your App ID to the `.env` files

3. **Verify setup**:
   ```bash
   just test           # Run tests
   just example-run    # Run example app
   ```

### Development Tools

We use several tools to maintain code quality:

- **Just**: Task runner for common development tasks
- **flutter_lints**: Official Flutter linting rules
- **dart format**: Code formatting
- **dart analyze**: Static analysis
- **flutter test**: Testing framework

## Contributing Guidelines

### Types of Contributions

We welcome contributions in many forms:

- 🐛 **Bug reports** and fixes
- ✨ **New features** and enhancements
- 📚 **Documentation** improvements
- 🧪 **Tests** and test coverage improvements
- 🎨 **Code quality** and refactoring
- 🌍 **Localization** and accessibility
- 💬 **Community support** in issues and discussions

### Before You Start

1. **Check existing issues** to avoid duplicate work
2. **Create an issue** for significant changes to discuss approach
3. **Start small** - begin with bug fixes or documentation
4. **Ask questions** if you need clarification

## Development Workflow

### Branch Strategy

- `main` - Stable release branch
- `feature/feature-name` - New features
- `bugfix/issue-description` - Bug fixes
- `docs/topic` - Documentation updates

### Making Changes

1. **Create a feature branch**:
   ```bash
   git checkout -b feature/your-feature-name
   ```

2. **Make your changes** following our [code style](#code-style)

3. **Write tests** for new functionality

4. **Run quality checks**:
   ```bash
   just check          # Run all quality checks
   just test           # Run tests
   just analyze        # Static analysis
   just format-check   # Check formatting
   ```

5. **Update documentation** as needed

6. **Commit your changes** with clear messages:
   ```bash
   git add .
   git commit -m "feat: add support for custom query operators
   
   - Implement $regex operator for pattern matching
   - Add comprehensive tests for new operators
   - Update documentation with examples
   
   Closes #123"
   ```

### Commit Message Format

We follow conventional commits format:

- `feat:` - New features
- `fix:` - Bug fixes
- `docs:` - Documentation changes
- `test:` - Test-related changes
- `refactor:` - Code refactoring
- `perf:` - Performance improvements
- `style:` - Code style changes
- `chore:` - Build process or auxiliary tool changes

## Testing

### Running Tests

```bash
# Run all tests
just test

# Run specific test suites
just test-unit           # Unit tests only
just test-integration    # Integration tests only
just test-coverage      # With coverage report

# Run specific test file
just test-specific test/query_engine_test.dart
```

### Writing Tests

- **Unit tests** for individual functions and classes
- **Integration tests** for full workflows
- **Widget tests** for UI components
- **Mock external dependencies** using `mocktail`

Example test structure:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:instantdb_flutter/instantdb_flutter.dart';

void main() {
  group('QueryEngine', () {
    late QueryEngine queryEngine;

    setUp(() {
      queryEngine = QueryEngine(mockStore);
    });

    test('should handle basic queries', () async {
      // Arrange
      final query = {'todos': {}};

      // Act
      final result = queryEngine.query(query);

      // Assert
      expect(result.value.isLoading, isTrue);
    });
  });
}
```

### Test Requirements

- **All new features** must include tests
- **Bug fixes** should include regression tests
- **Maintain test coverage** above 80%
- **Tests must be reliable** and not flaky

## Code Style

### Dart/Flutter Style

We follow the official [Dart style guide](https://dart.dev/guides/language/effective-dart/style) with these additions:

- **Use `flutter_lints`** linting rules
- **Prefer explicit types** for public APIs
- **Use meaningful variable names**
- **Add documentation** for public APIs
- **Keep functions focused** and single-purpose

### Code Formatting

```bash
# Format code
just format

# Check formatting
just format-check
```

### Documentation

- **Public APIs** must be documented with `///` comments
- **Complex algorithms** should have inline comments
- **Example usage** in documentation when helpful

Example:
```dart
/// Creates a reactive query for the specified entities.
///
/// The [query] parameter defines what data to fetch and how to filter it.
/// Returns a [Signal<QueryResult>] that updates automatically when data changes.
///
/// Example:
/// ```dart
/// final todosQuery = db.query({
///   'todos': {'where': {'completed': false}}
/// });
/// ```
Signal<QueryResult> query(Map<String, dynamic> query) {
  // Implementation
}
```

### Architecture Guidelines

- **Separation of concerns** - Keep business logic separate from UI
- **Dependency injection** - Use constructor injection for dependencies  
- **Reactive patterns** - Use Signals for state management
- **Error handling** - Proper error propagation and user-friendly messages
- **Performance** - Consider memory usage and rendering performance

## Submitting Changes

### Pull Request Process

1. **Push your branch** to your fork:
   ```bash
   git push origin feature/your-feature-name
   ```

2. **Create a Pull Request** on GitHub with:
   - Clear title describing the change
   - Detailed description of what and why
   - Link to related issues
   - Screenshots for UI changes
   - Breaking changes highlighted

3. **Ensure CI passes**:
   - All tests pass
   - Code analysis passes
   - Documentation builds
   - Example app works

4. **Respond to feedback** promptly and professionally

### Pull Request Template

```markdown
## Description
Brief description of changes

## Type of Change
- [ ] Bug fix
- [ ] New feature
- [ ] Breaking change
- [ ] Documentation update

## Testing
- [ ] Unit tests added/updated
- [ ] Integration tests added/updated
- [ ] Manual testing completed

## Checklist
- [ ] Code follows style guidelines
- [ ] Self-review completed
- [ ] Documentation updated
- [ ] No breaking changes (or clearly documented)
```

### Review Process

- **All PRs require review** from maintainers
- **Address feedback** constructively
- **Keep discussions focused** on the code
- **Be patient** - reviews take time
- **Learn from feedback** to improve future contributions

## Release Process

### Versioning

We use [Semantic Versioning](https://semver.org/):

- **MAJOR** version for incompatible API changes
- **MINOR** version for backwards-compatible functionality
- **PATCH** version for backwards-compatible bug fixes

### Release Workflow

Releases are handled by maintainers using our automated workflow:

```bash
# Complete release workflow
just release-full

# Or individual steps
just publish-workflow    # Validate everything
just version-minor      # Bump version
just changelog-generate # Update changelog
just release-create     # Create GitHub release
just publish           # Publish to pub.dev
```

See [ReleasingWorkflow.md](ReleasingWorkflow.md) for detailed release process.

## Development Resources

### Useful Commands

```bash
# Development
just dev-setup          # Initial setup
just example-run        # Run example app
just example-web        # Run web version
just watch             # Watch for changes

# Quality
just check             # All quality checks
just lint              # Run linter
just security          # Security audit
just deps-outdated     # Check dependency updates

# Documentation
just docs              # Generate API docs
just docs-serve        # Serve docs locally
just website-dev       # Run documentation website

# Release
just version-check     # Check version consistency
just publish-check     # Pre-publish validation
just publish-score     # Estimate pub.dev score
```

### Project Structure

```
├── lib/
│   ├── instantdb_flutter.dart     # Main entry point
│   └── src/                       # Implementation
│       ├── core/                  # Core InstantDB client
│       ├── storage/               # Local SQLite storage
│       ├── query/                 # Query engine
│       ├── sync/                  # Real-time sync
│       ├── reactive/              # Flutter widgets
│       └── auth/                  # Authentication
├── example/                       # Example application
├── test/                         # Test files
├── website/                      # Documentation website
└── scripts/                      # Development scripts
```

### Key Dependencies

- `signals_flutter` - Reactive state management
- `sqflite` - SQLite database
- `dio` - HTTP client
- `web_socket_channel` - WebSocket connections
- `uuid` - UUID generation
- `logging` - Structured logging

## Getting Help

### Communication Channels

- **GitHub Issues** - Bug reports and feature requests
- **GitHub Discussions** - Questions and community support  
- **Discord** - Real-time chat and collaboration
- **Email** - Contact maintainers for sensitive issues

### Documentation

- **API Documentation** - Generated from code comments
- **Website Documentation** - Comprehensive guides and tutorials
- **Example Code** - Working examples in `/example` folder
- **README** - Quick start and overview

### FAQ

**Q: How do I run tests locally?**
A: Use `just test` or `flutter test` to run the full test suite.

**Q: My PR failed CI checks, what should I do?**
A: Run `just check` locally to see the same checks, then fix any issues.

**Q: How do I add a new feature?**
A: Create an issue first to discuss the feature, then follow our development workflow.

**Q: Can I contribute documentation?**
A: Yes! Documentation improvements are very welcome. See the `website/` folder.

## Recognition

We value all contributions and maintain a list of contributors in our README. Significant contributions will be highlighted in our release notes.

## License

By contributing to InstantDB Flutter, you agree that your contributions will be licensed under the same MIT license that covers the project.

---

Thank you for contributing to InstantDB Flutter! 🎉

If you have questions about contributing, please don't hesitate to ask in our GitHub Discussions or create an issue.