# MCP LLM Testing Guide

This document explains how to run tests in the MCP LLM package.

## Test Types

This package has two types of tests:

1. **Unit Tests**: Run without external dependencies and don't make actual API calls
2. **Integration Tests**: Require API keys and make real API calls to LLM providers

## Running Tests

### Unit Tests Only

To run only unit tests (which don't require API keys):

```bash
dart test --exclude-tags=integration
```

### Integration Tests

To run integration tests, you need to set the appropriate API keys as environment variables:

```bash
# Set API keys
export OPENAI_API_KEY="your-openai-key"
export ANTHROPIC_API_KEY="your-claude-key"
export TOGETHER_API_KEY="your-together-key"

# Run integration tests
dart test --tags=integration
```

You only need to set keys for the services you want to test. Missing keys will cause tests for those providers to be skipped automatically.

### Using the Helper Script

Use the included helper script to run all tests:

```bash
# Run with no keys (only unit tests will run)
./run_tests.sh

# Run with specific keys
./run_tests.sh "your-openai-key" "your-claude-key" "your-together-key"
```

## Test Tags

Tests are tagged for easier filtering:

- `integration`: Tests that require API keys
- `openai`: Tests specific to OpenAI provider
- `claude`: Tests specific to Claude (Anthropic) provider
- `together`: Tests specific to Together AI provider
- `rag`: Tests for RAG functionality

You can run tests with specific tags:

```bash
# Run only OpenAI tests
dart test --tags=openai

# Run all RAG tests
dart test --tags=rag
```

## Troubleshooting

### API Keys Issues

If you see errors like:
```
Bad state: API key is required for OpenAI provider
```

It means you're trying to run integration tests without the required API keys. Either:
1. Set the appropriate environment variables
2. Run only unit tests with `--exclude-tags=integration`
3. Use the helper script which handles this automatically

### Running on CI/CD

For CI/CD environments, add API keys as secrets and use the following in your workflow:

```yaml
- name: Run tests
  env:
    OPENAI_API_KEY: ${{ secrets.OPENAI_API_KEY }}
    ANTHROPIC_API_KEY: ${{ secrets.ANTHROPIC_API_KEY }}
    TOGETHER_API_KEY: ${{ secrets.TOGETHER_API_KEY }}
  run: dart test
```

If you don't want to run integration tests in CI/CD:

```yaml
# Run all tests
dart test

# Run only integration tests
dart test --tags=integration

# Run only OpenAI tests
dart test --tags=openai

# Run only unit tests (excluding integration tests)
dart test --exclude-tags=integration
```