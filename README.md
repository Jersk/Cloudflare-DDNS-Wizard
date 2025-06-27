# 🧙‍♂️ Cloudflare DDNS Wizard

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Bash](https://img.shields.io/badge/shell-bash-green.svg)](https://www.gnu.org/software/bash/)
[![Cloudflare](https://img.shields.io/badge/Cloudflare-API-orange.svg)](https://api.cloudflare.com/)
[![Linux](https://img.shields.io/badge/OS-Linux-blue.svg)](https://www.linux.org/)
[![systemd](https://img.shields.io/badge/init-systemd-red.svg)](https://systemd.io/)

> **Professional Dynamic DNS automation for Cloudflare with guided setup wizard and intelligent management**

Perfect for **homelab enthusiasts**, **self-hosted services**, and anyone running servers on **dynamic IP connections**. This script provides a complete, production-ready solution for keeping your Cloudflare DNS records synchronized with your changing public IP address.

---

## 🚀 Quick Start

```bash
# Download and run the setup wizard
wget https://raw.githubusercontent.com/Jersk/cloudflare-ddns-wizard/main/setup.sh
chmod +x setup.sh
./setup.sh
```

**That's it!** The wizard will guide you through everything automatically. 🎯

---

## ✨ Key Features

### 🧙‍♂️ **Intelligent Setup Wizard**
- **Guided onboarding** for first-time users with step-by-step instructions
- **Smart DNS record selection** with real-time IP comparison
- **Automatic dependency checking** with install guidance
- **Interactive menus** with intuitive back navigation
- **Configuration validation** at every step

### 🛡️ **Enterprise-Grade Reliability**
- **Comprehensive error handling** with automatic recovery mechanisms
- **Network resilience** with multiple IP detection services
- **Concurrency locks** to prevent conflicting updates
- **Detailed logging** with automatic log rotation
- **Service monitoring** and health checks

### 🎯 **Flexible Configuration Modes**
- **Simple Mode**: Perfect for single domain/subdomain setups
- **Specific Mode**: Select exactly which DNS records to monitor
- **Advanced Mode**: Custom retry policies, intervals, and timeouts
- **Backup/Restore**: Save and restore your configurations

### 🔒 **Security First**
- **Secure token storage** with proper file permissions (600)
- **API token validation** before any operations
- **Non-root execution** for the service (runs as your user)
- **No hardcoded credentials** - everything stored securely

### 📊 **Management Dashboard**
- **Service status monitoring** with real-time information
- **Log viewing** and analysis tools
- **Manual test execution** with detailed feedback
- **System resilience testing** capabilities
- **Complete uninstall** with cleanup

---

## 📋 Requirements

### System Requirements
- **Linux** with systemd (Ubuntu 16+, Debian 8+, CentOS 7+, RHEL 7+, etc.)
- **Root/sudo access** for systemd service installation
- **Internet connection** for API calls and IP detection

### Dependencies
The wizard automatically checks for these and provides installation guidance:
- `curl` - HTTP client for API calls
- `jq` - JSON processor for API responses  
- `flock` - File locking (usually part of util-linux)
- `bash` - Shell interpreter (version 4.0+)

### Cloudflare Requirements
- **Cloudflare account** with your domains
- **API Token** with permissions:
  - `Zone:Zone:Read` (for all zones)
  - `Zone:DNS:Edit` (for all zones)

---

## 🔑 Cloudflare API Token Setup

1. Go to [Cloudflare API Tokens](https://dash.cloudflare.com/profile/api-tokens)
2. Click **"Create Token"**
3. Use **"Custom token"** template
4. Configure permissions:
   ```
   Zone - Zone:Read - All zones
   Zone - DNS:Edit - All zones
   ```
5. Add IP address filtering if desired (optional but recommended)
6. Copy the generated token - **you'll need it for the wizard**

> ⚠️ **Important**: Save your token securely. The script stores it with 600 permissions for security.

---

## 🎛️ Configuration Modes

### 🏠 Simple Mode *(Recommended for most users)*
Perfect for basic setups:
- Specify **one domain** and **one subdomain**
- Automatically manages all A records for that name
- Example: `home.example.com` or `@.example.com` (apex domain)

### 🎯 Specific Mode *(Advanced users)*
For complex setups:
- **Select specific DNS records** from multiple zones
- **Visual comparison** of current record IPs vs your public IP
- **Granular control** over which records get updated
- Perfect for managing multiple services

### ⚙️ Advanced Settings
Customize the behavior:
- **Update interval** (1min to 60min, default: 5min)
- **Retry policies** (1-10 retries with configurable delays)
- **Network timeouts** (60-900 seconds)
- **Logging verbosity** and error handling

---

## 📁 File Structure

After installation, these files are created:

```
📂 Installation Directory
├── 📄 setup.sh                    # This wizard script
├── 📄 cf-ddns.sh                  # Main DDNS updater (auto-generated)
└── 📂 utils/
    ├── 📄 config.env              # Configuration file
    ├── 🔒 .cloudflare_api_token   # API token (secure, 600 perms)
    └── 📄 cf-ddns.log             # Execution logs (auto-rotated)

📂 System Files
├── 📄 /etc/systemd/system/cf-ddns.service  # systemd service
└── 📄 /etc/systemd/system/cf-ddns.timer    # systemd timer
```

---

## 🔧 Management & Usage

### After Initial Setup
Run the wizard anytime to access the management dashboard:
```bash
./setup.sh
```

### Available Operations

| Option | Description |
|--------|-------------|
| 🔧 **Configuration Management** | Update API token, domains, advanced settings |
| ⚙️ **Service Management** | Start/stop/restart the service, view status |
| 📋 **View Logs** | Check recent activity, follow live logs |
| 🧪 **Manual Test Run** | Test configuration and run update manually |
| 🔍 **System Resilience Test** | Verify error handling and recovery |
| 💾 **Backup & Restore** | Save/restore your configurations |
| 🗑️ **Complete Uninstall** | Remove everything cleanly |
| 🔄 **Reset Configuration** | Start over with fresh settings |

### Command Line Usage
```bash
# Check service status
systemctl status cf-ddns.timer

# View recent logs
journalctl -u cf-ddns.service -n 20

# Manual execution
./cf-ddns.sh

# Follow live logs
journalctl -u cf-ddns.service -f
```

---

## 🔍 Monitoring & Troubleshooting

### Service Status
```bash
# Check if timer is active
systemctl is-active cf-ddns.timer

# View next scheduled runs
systemctl list-timers cf-ddns.timer

# Check service health
systemctl status cf-ddns.service
```

### Log Analysis
The script provides detailed logging:
- ✅ **INFO**: Normal operations and status updates
- ⚠️ **WARN**: Non-critical issues and recoverable errors  
- ❌ **ERROR**: Critical issues requiring attention
- 📊 **Summary**: Update statistics and completion status

### Common Issues & Solutions

| Issue | Solution |
|-------|----------|
| ❌ API token invalid | Run wizard → Configuration → Update API Token |
| ❌ DNS record not found | Check domain is in Cloudflare, verify spelling |
| ❌ Permission denied | Run: `./setup.sh` → Configuration → Fix Permissions |
| ❌ Service won't start | Check logs: `journalctl -u cf-ddns.service -n 50` |
| ❌ Network timeout | Increase timeout in Advanced Settings |

---

## 🌟 Advanced Features

### Backup & Restore
- **Automatic backup creation** before major changes
- **Named backups** with timestamps
- **Full configuration restore** capability
- **Backup verification** and integrity checks

### Error Recovery
- **Multiple IP detection services** with failover
- **Automatic retry** with exponential backoff
- **Graceful error handling** continues on non-critical failures
- **Detailed error reporting** for troubleshooting

### Security Features
- **API token encryption** at rest
- **File permission validation** and auto-correction
- **User isolation** (service runs as your user, not root)
- **Minimal privilege principle** throughout

---

## 🚦 System Behavior

### Default Operation
Once enabled, the service automatically:
- 🔍 **Checks your public IP** every 5 minutes
- 🔄 **Updates DNS records** only when IP changes
- 🚀 **Starts automatically** after system boot/reboot
- 📝 **Logs all activities** for monitoring
- 🛡️ **Handles errors gracefully** with retry logic

### Update Process
1. **Detect current public IP** from multiple reliable sources
2. **Fetch existing DNS records** from Cloudflare
3. **Compare IPs** and identify records needing updates  
4. **Update only changed records** (efficient API usage)
5. **Verify updates** and log results
6. **Handle any errors** with appropriate retry logic

---

## 🤝 Contributing

We welcome contributions! Here's how you can help:

### 🐛 Bug Reports
- Use the [Issues](https://github.com/Jersk/cloudflare-ddns-wizard/issues) page
- Include your **Linux distribution and version**
- Provide **relevant log excerpts**
- Describe **steps to reproduce**

### 💡 Feature Requests
- Open an issue with the **enhancement** label
- Describe your **use case** and **expected behavior**
- Consider **implementation challenges**

### 🔧 Pull Requests
1. **Fork** the repository
2. Create a **feature branch**: `git checkout -b feature/amazing-feature`
3. **Test thoroughly** on multiple Linux distributions
4. **Update documentation** if needed
5. Submit a **pull request** with detailed description

---

## 📚 Documentation

### Wiki & Guides
Visit our [Wiki](https://github.com/Jersk/cloudflare-ddns-wizard/wiki) for:
- 📖 **Detailed setup guides** for different scenarios
- 🏗️ **Architecture documentation** and design decisions
- 🔧 **Troubleshooting guides** for common issues
- 💡 **Best practices** and optimization tips
- 🎯 **Use case examples** and configurations

### API Reference
The script uses [Cloudflare API v4](https://api.cloudflare.com/):
- **Authentication**: Bearer tokens
- **Rate limiting**: Respects Cloudflare limits
- **Error handling**: Comprehensive response processing

---

## 📝 License

This project is licensed under the **MIT License** - see the [LICENSE](LICENSE) file for details.

### What this means:
- ✅ **Commercial use** allowed
- ✅ **Modification** allowed  
- ✅ **Distribution** allowed
- ✅ **Private use** allowed
- ❌ **No warranty** provided
- ❌ **No liability** accepted

---

## 🙏 Acknowledgments

- **Cloudflare** for their excellent API and documentation
- **systemd** community for reliable service management
- **jq** developers for JSON processing capabilities
- **Linux distributions** for providing stable platforms
- **Open source community** for inspiration and feedback

---

## 📞 Support

### Need Help?
1. 📖 Check the [Wiki](https://github.com/Jersk/cloudflare-ddns-wizard/wiki) first
2. 🔍 Search [existing issues](https://github.com/Jersk/cloudflare-ddns-wizard/issues)
3. 💬 Open a [new issue](https://github.com/Jersk/cloudflare-ddns-wizard/issues/new) if needed
4. 📧 Include relevant logs and system information

### Community
- 💬 **Discussions**: Share your setups and experiences
- 🐛 **Issues**: Report bugs and request features  
- 🔧 **Pull Requests**: Contribute improvements
- ⭐ **Star the repo** if you find it useful!

---

<div align="center">

### 🌟 Star History

[![Star History Chart](https://api.star-history.com/svg?repos=Jersk/cloudflare-ddns-wizard&type=Date)](https://star-history.com/#Jersk/cloudflare-ddns-wizard&Date)

---

**Made with ❤️ for the homelab community**

[⬆ Back to top](#-cloudflare-ddns-wizard)

</div>
