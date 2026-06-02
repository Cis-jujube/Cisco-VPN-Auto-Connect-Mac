# VPN Auto-Connect

Cisco Secure Client 自动连接工具，支持 DUO 双因素认证、多配置管理、GUI 界面和二维码解码。

Cisco Secure Client auto-connect tool with DUO 2FA, multi-profile management, GUI, and QR decoder.

---

## 功能特性 / Features

| 功能 / Feature | 说明 / Description |
|---|---|
| 一键连接 / One-click connect | `vpn-connect` 自动完成 6 步登录 / Auto 6-step login |
| DUO 双因素 / DUO 2FA | 支持 Push/Phone/SMS/TOTP 四种方式 / 4 methods supported |
| 多配置管理 / Multi-profile | `vpn-add`/`vpn-use`/`vpn-ls` 管理多个 VPN / Manage multiple VPNs |
| 快速设置 / Quick settings | `vpn-set server <value>` 单项修改 / Change individual settings |
| GUI 界面 / GUI manager | `vpn-gui` 图形化管理 / Visual manager with status display |
| QR 解码 / QR decoder | `qrgui` 解码 DUO 二维码提取 TOTP 密钥 / Extract TOTP secrets from QR |
| 安全存储 / Secure storage | Windows DPAPI 加密凭据 / DPAPI encrypted credentials |

---

## 安装 / Installation

### 前置条件 / Prerequisites

- Windows 10/11
- [Cisco Secure Client](https://www.cisco.com/) 已安装 (含 `vpncli.exe`)
- PowerShell 5.1+ (Windows 自带 / Built-in)
- Python 3.10+ (仅 QR 工具和 GUI 需要 / Only for QR tools and GUI)

### 安装步骤 / Setup Steps

```powershell
# 1. 克隆仓库 / Clone repository
git clone https://github.com/YOUR_USERNAME/vpn-auto-connect.git
cd vpn-auto-connect

# 2. 添加 cmd/ 到 PATH (全局可用) / Add cmd/ to PATH
[Environment]::SetEnvironmentVariable(
    "PATH",
    $env:PATH + ";$(Get-Location)\cmd",
    "User"
)

# 3. 安装 QR 工具依赖 (可选) / Install QR dependencies (optional)
pip install pyzbar Pillow

# 4. 重启终端 / Restart terminal
```

---

## Duke Kunshan VPN 配置指南 / Duke Kunshan VPN Setup Guide

### 首次配置 / First-Time Setup

```powershell
# 运行首次设置向导 / Run setup wizard
vpn-reconfig
```

按提示输入以下信息 / Enter the following when prompted:

```
[1/4] VPN Server: portal.dukekunshan.edu.cn
[2/4] VPN Group:  -Default-           (或留空 / or leave blank)
[3/4] Port:       443                  (直接回车用默认 / Enter for default)
[4/4] Protocol:   ssl                  (直接回车用默认 / Enter for default)
```

然后输入你的 DKU 账号密码 / Then enter your DKU credentials:

```
Username: your-netid
Password: ********
```

### DUO 登录方式 / DUO Login Methods

DKU VPN 使用 DUO 双因素认证，支持以下方式：

DKU VPN uses DUO 2FA with these methods:

| 方式 / Method | 命令 / Command | 说明 / Description |
|---|---|---|
| **Push** (推荐 / Recommended) | `vpn-connect` | 发送推送通知到手机，点"Approve"即可 / Push to phone, tap Approve |
| **Phone** | `vpn-connect phone` | 打电话验证 / Call your phone |
| **SMS** | `vpn-connect sms` | 发送短信验证码 / Send SMS code |
| **Passcode** (全自动 / Full auto) | `vpn-connect passcode` | 自动生成 TOTP 验证码 / Auto-generate TOTP code |

### 设置全自动 TOTP 登录 / Setup Full-Auto TOTP Login

```powershell
# 步骤 1: 用 QR 工具解码 DUO 二维码 / Step 1: Decode DUO QR code
qrgui
# -> 打开 DUO 二维码图片 -> 复制 Secret 字段
# -> Open DUO QR code image -> Copy the Secret field

# 步骤 2: 保存 TOTP 密钥 / Step 2: Save TOTP secret
vpn-totp
# -> 粘贴刚才复制的 Secret
# -> Paste the Secret you copied

# 步骤 3: 全自动连接 / Step 3: Full-auto connect
vpn-connect passcode
# -> 无需任何操作，自动完成登录
# -> No interaction needed, fully automated
```

---

## 命令速查表 / Command Reference

### 基础命令 / Basic Commands

```powershell
vpn              # 显示所有命令 / List all commands
vpn-connect      # 连接 VPN (DUO Push) / Connect (DUO Push)
vpn-disconnect   # 断开 VPN / Disconnect
vpn-status       # 显示连接状态 / Show connection status
vpn-help         # 显示详细帮助 / Show detailed help
```

### 配置管理 / Configuration

```powershell
vpn-setup        # 保存凭据 (旧版) / Save credentials (legacy)
vpn-reconfig     # 清除配置重新设置 / Clear and re-setup
vpn-totp         # 保存 TOTP 密钥 / Save TOTP secret
```

### 多配置 Profile / Multi-Profile

```powershell
vpn-add          # 添加新配置 / Add new profile
vpn-ls           # 列出所有配置 / List all profiles
vpn-use dku      # 切换到 dku 配置 / Switch to dku profile
vpn-rm old       # 删除 old 配置 / Remove old profile
vpn-edit dku     # 编辑 dku 配置 / Edit dku profile
```

### 快速设置 / Quick Settings

```powershell
vpn-set server portal.dukekunshan.edu.cn   # 修改服务器 / Change server
vpn-set group "-Default-"                   # 修改分组 / Change group
vpn-set port 8443                           # 修改端口 / Change port
vpn-set protocol ipsec                      # 修改协议 / Change protocol
vpn-set user newuser                        # 修改用户名 / Change username
vpn-set duo passcode                        # 修改 DUO 方式 / Change DUO method
```

### GUI 和 QR 工具 / GUI and QR Tools

```powershell
vpn-gui          # 启动 VPN 图形界面 / Launch VPN GUI
qrgui            # 启动 QR 解码 GUI / Launch QR decoder GUI
qrdecode img.png # 命令行解码 QR / CLI QR decode
```

---

## 多配置使用示例 / Multi-Profile Examples

```powershell
# 添加 DKU VPN / Add DKU VPN
vpn-add
# Name: dku
# Server: portal.dukekunshan.edu.cn
# Group: -Default-
# Port: 443
# Protocol: ssl

# 添加公司 VPN / Add company VPN
vpn-add
# Name: company
# Server: vpn.company.com
# Group: (留空 / blank)
# Port: 443
# Protocol: ssl

# 查看所有配置 / List all profiles
vpn-ls
#   * dku       portal.dukekunshan.edu.cn:443
#     company   vpn.company.com:443

# 切换到公司 VPN / Switch to company VPN
vpn-use company

# 连接 / Connect
vpn-connect
```

---

## 文件结构 / File Structure

```
vpn-auto-connect/
├── vpn-auto-connect.ps1      # 核心脚本 (PowerShell) / Core script
├── vpn_auto_connect.py       # 备选脚本 (Python + wexpect) / Alternative (Python)
├── vpn-gui.bat               # GUI 启动入口 / GUI launcher
├── AGENTS.md                 # Agent 文档 / Agent documentation
├── README.md                 # 本文档 / This file
├── LICENSE                   # MIT License
├── .gitignore
│
├── cmd/                      # 全局命令入口 / Global command entry points
│   ├── vpn.cmd               # 显示命令列表 / List commands
│   ├── vpn-connect.cmd       # 连接 / Connect
│   ├── vpn-disconnect.cmd    # 断开 / Disconnect
│   ├── vpn-status.cmd        # 状态 / Status
│   ├── vpn-setup.cmd         # 设置凭据 / Setup credentials
│   ├── vpn-totp.cmd          # 保存 TOTP / Save TOTP
│   ├── vpn-reconfig.cmd      # 重新配置 / Reconfigure
│   ├── vpn-help.cmd          # 帮助 / Help
│   ├── vpn-add.cmd           # 添加 Profile / Add profile
│   ├── vpn-ls.cmd            # 列出 Profile / List profiles
│   ├── vpn-use.cmd           # 切换 Profile / Switch profile
│   ├── vpn-rm.cmd            # 删除 Profile / Remove profile
│   ├── vpn-edit.cmd          # 编辑 Profile / Edit profile
│   ├── vpn-set.cmd           # 快速设置 / Quick settings
│   └── vpn-gui.cmd           # 启动 GUI / Launch GUI
│
└── tools/                    # 辅助工具 / Auxiliary tools
    ├── qrdecode.py           # QR 解码 (CLI) / QR decoder (CLI)
    ├── qrdecode_gui.py       # QR 解码 (GUI) / QR decoder (GUI)
    ├── qrdecode.bat          # CLI 入口 / CLI launcher
    └── qrgui.bat             # GUI 入口 / GUI launcher
```

### 配置目录 / Config Directory

```
~/.vpn-auto-connect/          # 自动生成 / Auto-created
├── config.json               # 服务器配置 (旧版) / Server config (legacy)
├── credentials.xml           # 加密凭据 (旧版) / Encrypted credentials (legacy)
├── totp.xml                  # 加密 TOTP 密钥 / Encrypted TOTP secret
├── profiles.json             # Profile 索引 / Profile index
├── active_profile            # 当前活跃 Profile / Active profile name
└── profiles/                 # 多配置目录 / Multi-profile directory
    ├── dku/
    │   ├── config.json
    │   ├── credentials.xml
    │   └── totp.xml
    └── company/
        ├── config.json
        └── credentials.xml
```

---

## 安全说明 / Security

- **凭据加密**: 使用 Windows DPAPI (`CurrentUser` scope)，仅当前 Windows 用户可解密
- **Credentials encrypted**: Uses Windows DPAPI (CurrentUser scope), only the current Windows user can decrypt
- **配置目录权限**: 自动设置为仅当前用户可访问
- **Config dir permissions**: Auto-restricted to current user only
- **不要提交凭据**: `.gitignore` 已排除配置目录
- **Never commit credentials**: `.gitignore` excludes the config directory

---

## 依赖 / Dependencies

### 核心 (无额外依赖) / Core (no extra dependencies)

- PowerShell 5.1+ (Windows 自带 / Built-in)
- Cisco Secure Client (含 vpncli.exe / with vpncli.exe)

### QR 工具 (可选) / QR Tools (optional)

```bash
pip install pyzbar Pillow
```

### Python VPN 脚本 (可选) / Python VPN Script (optional)

```bash
pip install wexpect
```

---

## License

[MIT](LICENSE)
