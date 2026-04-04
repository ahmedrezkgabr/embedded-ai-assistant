# Security Policy

## Supported versions

| Version | Supported |
|---------|-----------|
| main    | ✅ |
| older   | ❌ |

## Threat model

This system is designed for local network deployment with no internet-facing exposure.
The intended security boundary is:

- The device is on a trusted local network
- The web UI is accessible to all devices on the LAN
- No authentication is implemented (by design for home/office single-user use)
- No data is sent outside the local network

## What is NOT in scope

- Internet exposure without a reverse proxy + auth
- Multi-user access control
- Encrypted model storage
- Secure boot (hardware-dependent)

## Reporting a vulnerability

Please report vulnerabilities privately via GitHub Security Advisories:

https://github.com/ahmedrezkgabr/embedded-ai-assistant/security/advisories/new

Do not open a public GitHub issue for security vulnerabilities.

Expected response time: within 7 days.

## Known security considerations

- CORS allows all RFC-1918 private IP ranges
- No authentication on the web UI
- Root login enabled in debug Yocto builds (`debug-tweaks` IMAGE_FEATURE)
- Temp files written to `/tmp` (world-readable)