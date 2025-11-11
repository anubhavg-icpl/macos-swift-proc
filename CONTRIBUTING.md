# Contributing to DualDaemonApp

## Code Standards

All contributions must meet the following standards:

### Swift Code Style

- Follow Swift API Design Guidelines
- Use meaningful variable and function names
- Maximum line length: 120 characters
- Use SwiftLint for code formatting
- Document public APIs with doc comments

### Error Handling

**MANDATORY**: Proper error handling is non-negotiable.

❌ **NEVER** do this:
```swift
try? someOperation()  // Silent failure - unacceptable
```

✅ **ALWAYS** do this:
```swift
do {
    try someOperation()
} catch {
    logger.error("Operation failed: \(error)")
    // Handle error appropriately
    throw DaemonError.operationFailed(underlying: error)
}
```

### Security Requirements

1. **No Hardcoded Credentials**: All sensitive data via environment variables
2. **Input Validation**: Validate all external input
3. **Error Messages**: Don't expose sensitive information in errors
4. **Logging**: Don't log credentials or sensitive data

### Testing Requirements

All new code must include:
- Unit tests with >80% coverage
- Integration tests for message handling
- Error case testing
- Performance tests for critical paths

### Documentation

- Public APIs must have doc comments
- Complex logic must have inline comments explaining WHY
- README updated for new features
- CHANGELOG updated

## Pull Request Process

1. **Fork and Branch**: Create feature branch from `main`
2. **Code**: Implement changes following standards above
3. **Test**: All tests pass, coverage maintained
4. **Lint**: Code passes SwiftLint checks
5. **Document**: Update docs and CHANGELOG
6. **PR**: Submit with clear description

### PR Title Format

```
[TYPE] Brief description

Types: FIX, FEAT, DOCS, TEST, REFACTOR, PERF, SECURITY
```

### PR Description Template

```markdown
## Description
[Clear description of changes]

## Motivation
[Why is this change needed?]

## Changes
- Change 1
- Change 2

## Testing
[How was this tested?]

## Checklist
- [ ] Tests added/updated
- [ ] Documentation updated
- [ ] No breaking changes (or documented)
- [ ] Security reviewed
- [ ] Performance impact assessed
```

## Code Review Criteria

Your PR will be reviewed for:

1. **Correctness**: Does it work? Does it solve the problem?
2. **Security**: Any vulnerabilities? Proper error handling?
3. **Performance**: Any performance regressions?
4. **Maintainability**: Is it readable? Well-structured?
5. **Testing**: Adequate test coverage?
6. **Documentation**: Is it documented?

## Common Rejection Reasons

PRs will be rejected for:

- Silent error handling (`try?` without justification)
- Hardcoded credentials or secrets
- Missing tests
- Breaking changes without major version bump
- Security vulnerabilities
- Poor code quality
- Insufficient documentation

## Development Setup

```bash
# Clone repository
git clone https://github.com/anubhavg-icpl/macos-swift-proc.git
cd macos-swift-proc

# Install dependencies
swift package resolve

# Build
swift build

# Run tests
swift test

# Generate documentation
swift doc generate
```

## Questions?

Open an issue with the `question` label for clarification on contribution guidelines.
