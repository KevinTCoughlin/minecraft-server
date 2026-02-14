# Security Policy

## Supported Versions

We actively support the following versions with security updates:

| Version | Supported          |
| ------- | ------------------ |
| 1.x.x   | :white_check_mark: |
| < 1.0   | :x:                |

## Reporting a Vulnerability

We take security vulnerabilities seriously. If you discover a security issue, please follow these steps:

### 1. Do NOT Open a Public Issue

Please **do not** create a public GitHub issue for security vulnerabilities, as this could put users at risk.

### 2. Report Privately

Report security vulnerabilities through one of these methods:

- **GitHub Security Advisories**: Use the [Security Advisories page](https://github.com/KevinTCoughlin/minecraft-server/security/advisories/new) (preferred)
- **Email**: Contact the maintainers privately

### 3. Provide Details

Include the following information in your report:

- Description of the vulnerability
- Steps to reproduce the issue
- Potential impact
- Any suggested fixes (if available)
- Your contact information

### 4. Response Timeline

- **Initial Response**: Within 48 hours
- **Status Update**: Within 7 days
- **Fix Timeline**: Depends on severity
  - Critical: 1-7 days
  - High: 7-30 days
  - Medium/Low: 30-90 days

## Security Measures

This project implements several security measures:

### Automated Security Scanning

- **CodeQL**: Continuous security analysis of code
- **Dependabot**: Automated dependency vulnerability scanning
- **Trivy**: Container image vulnerability scanning
- **SBOM**: Software Bill of Materials generation

### Build Security

- **Gradle Wrapper Validation**: Ensures integrity of build scripts
- **Dependency Verification**: Checks for known vulnerabilities
- **Eclipse Temurin**: Uses trusted OpenJDK distribution
- **Multi-stage Docker Builds**: Minimizes attack surface

### Runtime Security

- **Non-root Containers**: Docker images run as unprivileged user
- **Minimal Base Images**: Alpine Linux for smaller attack surface
- **RCON Password Protection**: Secure remote administration
- **Network Isolation**: Proper Docker network configuration

## Security Best Practices

When using this project, we recommend:

### Server Configuration

1. **Change Default Passwords**
   - Update RCON password in `server.properties`
   - Use strong, unique passwords

2. **Enable Whitelist**
   - Use whitelist mode for private servers
   - Regularly review player permissions

3. **Regular Updates**
   - Keep Paper server updated
   - Update plugins regularly
   - Apply security patches promptly

4. **Network Security**
   - Use firewall rules to restrict access
   - Consider using a reverse proxy
   - Enable DDoS protection if needed

### Plugin Development

1. **Input Validation**
   - Validate all player input
   - Sanitize user-generated content
   - Use parameterized queries

2. **Permission Checks**
   - Always verify permissions before actions
   - Follow principle of least privilege
   - Use Paper's permission system

3. **Dependency Management**
   - Keep dependencies updated
   - Review dependency security advisories
   - Use dependency verification

4. **Code Review**
   - Review all code changes
   - Use automated security scanning
   - Follow secure coding practices

## Known Security Considerations

### Minecraft Server

- Minecraft servers are inherently exposed to network traffic
- Players can potentially exploit game mechanics
- Mods and plugins can introduce vulnerabilities

### Mitigation Strategies

1. **Use Paper** instead of vanilla Minecraft for better security
2. **Regular Backups** to recover from incidents
3. **Monitor Logs** for suspicious activity
4. **Rate Limiting** to prevent abuse
5. **Player Reporting** system for moderation

## Security Updates

Security updates are released as:

- **Patch Releases**: For security fixes (e.g., 1.0.1)
- **Security Advisories**: Published on GitHub
- **Release Notes**: Include security fix details

Subscribe to repository releases to stay informed.

## Credits

We appreciate responsible disclosure and will acknowledge security researchers who report vulnerabilities (unless they prefer to remain anonymous).

## Questions?

For security-related questions that are not vulnerabilities, please:

1. Check existing [Discussions](https://github.com/KevinTCoughlin/minecraft-server/discussions)
2. Review the [documentation](README.md)
3. Open a new discussion (not an issue) for questions

---

Thank you for helping keep this project secure! 🔒
