# Security Policy

## Overview

Tapback is a local development tool designed to monitor and control terminal sessions from mobile devices over a local network. It is **not intended for production or public network use**.

## Security Considerations

### Network Exposure

- The server binds to `0.0.0.0`, making it accessible from any device on the local network
- Use only on trusted networks (home, private office)
- Do not expose to the public internet without additional security measures

### PIN Authentication

- 4-digit PIN is generated randomly on each server start
- PIN is displayed only in the Mac app window
- Recommended to keep PIN enabled (default)
- Session cookies expire after 24 hours

### tmux Session Access

- The app provides full terminal access to tmux sessions
- Anyone with network access and PIN can execute commands
- Be cautious about which sessions you expose

## Recommendations

1. **Use on trusted networks only**
2. **Keep PIN authentication enabled**
3. **Use ngrok or similar tunneling with caution** - adds encryption but exposes to internet
4. **Stop the server when not in use**
5. **Do not run sensitive operations** while the server is accessible

## Reporting Vulnerabilities

If you discover a security vulnerability, please open an issue on GitHub or contact the maintainer directly.

## Disclaimer

This tool is provided as-is for local development convenience. Users are responsible for ensuring appropriate security measures in their environment.
