# Swift OTA Host

A standalone Swift command-line utility for iOS App Over-The-Air (OTA) distribution. This is a Swift implementation of the TypeScript OTA host script, providing better performance and easier distribution as a single binary.

## Features

- 🚀 **Fast & Lightweight**: Compiled Swift binary with minimal dependencies
- 📱 **iOS OTA Distribution**: Serves IPA files for over-the-air installation
- 🔒 **HTTPS Support**: Self-signed certificates for development, Tailscale certs for production
- 🌐 **Tailscale Integration**: Automatic certificate fetching and hostname resolution
- 📦 **IPA Metadata Extraction**: Automatically extracts app info from IPA files
- 🎨 **Clean Install UI**: Beautiful web interface for app installation
- ⚡ **One-shot Mode**: Exit after serving one IPA (useful for CI/CD)

## Installation

### Build from Source

```bash
git clone <repository-url>
cd swift-ota-host
swift build -c release
```

The binary will be available at `.build/release/swift-ota-host`.

### Using Swift Package Manager

```bash
swift run swift-ota-host --help
```

## Usage

### Basic Usage

```bash
# Development mode (self-signed certs, localhost:8443)
swift-ota-host --dev

# Production mode (Tailscale certs, port 443)
sudo swift-ota-host --port 443

# Custom port
swift-ota-host --dev --port 9000

# Use specific IPA file
swift-ota-host --dev --ipa MyApp.ipa

# Exit after first download (useful for CI/CD)
swift-ota-host --dev --once
```

### Command Line Options

```
USAGE: swift-ota-host [OPTIONS]

OPTIONS:
  --dev                   Development mode (self-signed certs, localhost)
  --port <port>          Server port (default: 443 prod, 8443 dev)
  --ipa <path>           Use specific IPA file
  --once                 Exit after serving the first IPA file
  --no-https             Disable HTTPS (not recommended)
  -h, --help             Show help information
```

## How It Works

1. **IPA Discovery**: Scans current directory for `.ipa` files
2. **Metadata Extraction**: Extracts bundle ID, version, and app name from IPA
3. **Certificate Setup**: 
   - Dev mode: Generates self-signed certificates
   - Production: Fetches certificates from Tailscale
4. **Server Start**: Starts HTTPS server with routes:
   - `/` - Install page with app info
   - `/manifest.plist` - iOS installation manifest
   - `/latest.ipa` - IPA file download
5. **Installation**: Users visit the URL on iOS Safari to install

## Requirements

- macOS 13.0+
- Swift 5.9+
- OpenSSL (for certificate generation)
- Tailscale (for production mode)

## Development Mode vs Production Mode

### Development Mode (`--dev`)
- Uses self-signed certificates
- Binds to localhost
- Default port: 8443
- No Tailscale required

### Production Mode
- Uses Tailscale certificates
- Binds to all interfaces
- Default port: 443 (requires sudo)
- Requires Tailscale to be running

## Project Structure

```
swift-ota-host/
├── Package.swift
├── Sources/swift-ota-host/
│   ├── main.swift              # CLI entry point
│   ├── OTAHost.swift           # Main host class
│   ├── Models/                 # Data models
│   │   ├── IPAInfo.swift
│   │   ├── ServerConfig.swift
│   │   ├── TailscaleStatus.swift
│   │   └── OTAError.swift
│   ├── Services/               # Service classes
│   │   ├── IPAService.swift
│   │   ├── CertificateService.swift
│   │   ├── TailscaleService.swift
│   │   ├── ShellService.swift
│   │   └── Logger.swift
│   └── Server/                 # HTTP server
│       ├── HTTPServer.swift
│       └── Templates.swift
└── README.md
```

## Dependencies

- **SwiftNIO**: High-performance HTTP server
- **SwiftNIO-SSL**: TLS/SSL support
- **ZipFoundation**: IPA archive processing
- **ArgumentParser**: Command-line argument parsing

## Comparison with TypeScript Version

| Feature | TypeScript | Swift |
|---------|------------|-------|
| Performance | Node.js runtime | Compiled binary |
| Memory Usage | Higher | Lower |
| Dependencies | npm packages | Single binary |
| Distribution | Requires Node.js | Standalone executable |
| Type Safety | Runtime checks | Compile-time checks |
| Async/Await | Yes | Yes (Swift 5.5+) |

## Examples

### Development Workflow

```bash
# Start development server
swift-ota-host --dev

# Output:
# [2024-01-15T10:30:00.000Z] INFO: OTA Host - iOS App Over-The-Air Distribution
# [2024-01-15T10:30:00.001Z] INFO: Using IPA: MyApp v1.0.0
# [2024-01-15T10:30:00.002Z] INFO: 🚀 OTA Server started
# [2024-01-15T10:30:00.003Z] INFO: 📱 App: MyApp v1.0.0
# [2024-01-15T10:30:00.004Z] INFO: 🌐 Install URL: https://localhost:8443/
# [2024-01-15T10:30:00.005Z] INFO: ⚙️  Mode: Development
```

### CI/CD Integration

```bash
# Build and serve IPA once
swift build -c release
.build/release/swift-ota-host --dev --once --port 8080
```

## Error Handling

The tool provides helpful error messages:

- **No IPA files found**: Suggests checking current directory
- **Tailscale not available**: Suggests using `--dev` flag
- **Certificate generation failed**: Suggests installing OpenSSL
- **Invalid port**: Validates port range (1-65535)

## License

MIT License - see LICENSE file for details.