# Security Policy

## Supported Versions

| Version | Supported |
|---------|-----------|
| 0.0.x   | ✅        |

## Reporting a Vulnerability

If you discover a security vulnerability in `api_plus`, please report it responsibly.

### How to Report

1. **Do NOT create a public GitHub issue** for security vulnerabilities
2. Email the maintainer at the contact listed on the GitHub profile
3. Include:
   - Description of the vulnerability
   - Steps to reproduce
   - Potential impact
   - Suggested fix (if any)

### What to Expect

- **Acknowledgment**: Within 48 hours of receiving your report
- **Assessment**: Within 1 week, we will assess the vulnerability and determine its severity
- **Fix**: Critical vulnerabilities will be patched as soon as possible
- **Disclosure**: We will coordinate with you on the disclosure timeline

### Scope

The following are in scope for security reports:

- Data leakage through logging (e.g., sensitive data not being masked)
- Cache poisoning vulnerabilities
- Insecure default configurations
- Dependency vulnerabilities

### Out of Scope

- Vulnerabilities in upstream packages (dio, http) — report these to their maintainers
- Issues that require physical access to the device
- Social engineering attacks

## Best Practices

When using `api_plus`, ensure you:

1. **Always configure `maskedKeys`** to include all sensitive header names and body keys
2. **Disable logging in production** or use `LogLevel.none` / `LogLevel.error`
3. **Use HTTPS** for all API endpoints
4. **Implement `CacheStore` encryption** for sensitive cached data
