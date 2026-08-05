# Contributing to api_plus

Thank you for your interest in contributing to `api_plus`! This document provides guidelines and information about contributing.

## Getting Started

1. Fork the repository on GitHub
2. Clone your fork locally
3. Create a feature branch from `main`
4. Make your changes
5. Submit a pull request

## Development Setup

```bash
# Clone the repo
git clone https://github.com/nisargratani/api_plus.git
cd api_plus

# Get dependencies
dart pub get

# Run tests
dart test

# Run analysis
dart analyze --fatal-infos

# Format code
dart format .
```

## Code Standards

### Style

- Follow [Effective Dart](https://dart.dev/effective-dart) guidelines
- Use `dart format` to format all code
- Every public API must have dartdoc documentation
- Every class, method, and parameter must be documented

### Architecture

- Core logic goes in `lib/src/core/`, `lib/src/interceptors/`, etc.
- Adapter-specific code goes in `lib/src/adapters/<client>/`
- No adapter should duplicate core logic — use `InterceptorPipeline` mixin
- New features should be interface-based for extensibility

### Testing

- Write tests for all new code
- Target 95%+ code coverage
- Include happy path, edge cases, and failure cases
- Use `mocktail` for mocking

## Pull Request Process

1. **Ensure all tests pass**: Run `dart test`
2. **Ensure zero analyzer issues**: Run `dart analyze --fatal-infos`
3. **Ensure proper formatting**: Run `dart format --output=none --set-exit-if-changed .`
4. **Update CHANGELOG.md** with your changes under an `## Unreleased` section
5. **Update documentation** if you changed public APIs
6. **Add tests** for new functionality

## Reporting Issues

- Use [GitHub Issues](https://github.com/nisargratani/api_plus/issues)
- Include a minimal reproducible example
- Include the Dart/Flutter SDK version
- Include the `api_plus` version
- Include the full error message and stack trace

## Code of Conduct

This project follows the [Contributor Covenant Code of Conduct](CODE_OF_CONDUCT.md).
