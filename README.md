# sing-box Linux 全局 TUN 一键部署脚本

这是一个简单易用的 sing-box 部署脚本，只需输入 SOCKS5 代理信息即可实现 Linux 系统全局代理。

## 功能特点

- 🚀 一键安装，自动下载最新版本
- 🇨🇳 支持国内镜像源，下载更快
- ✅ 自动验证 SOCKS5 代理连接
- 🎯 提供 prox 命令，交互式管理
- 🔧 只需输入 SOCKS5 代理信息
- 🌐 全局 TUN 模式，所有流量自动代理
- 🇨🇳 智能分流，国内流量直连
- 🔄 支持一键卸载
- 📦 自动配置 systemd 服务

## 系统要求

- Linux 系统（支持 x86_64、ARM64、ARMv7）
- Root 权限
- systemd 支持

## 快速开始

### 一键安装

```bash
curl -fsSL https://raw.githubusercontent.com/Last2334/onekey-p-linux/main/install.sh | sudo bash
```

如果无法访问 GitHub，请先在主机上开启全局代理，或下载脚本后运行：

```bash
# 下载脚本
curl -O https://raw.githubusercontent.com/Last2334/onekey-p-linux/main/install.sh

# 添加执行权限
chmod +x install.sh

# 运行安装
sudo ./install.sh
```

安装过程中会提示：
1. 选择下载源（推荐选择国内镜像）
2. 输入 SOCKS5 服务器地址（必填）
3. 输入 SOCKS5 端口（默认 1080）
4. 是否需要认证（可选）
5. 用户名和密码（如果需要认证）
6. 自动验证代理连接

安装完成后，使用 `sudo prox` 命令打开管理菜单。

### 下载源说明

安装过程中会提示选择 sing-box 的下载源：
- GitHub 官方源：适合国外服务器或有代理的环境
- ghproxy.com 镜像：国内镜像（推荐）
- ghps.cc 镜像：备用镜像
- gh-proxy.com 镜像：备用镜像

注意：如果无法访问 GitHub，请先在主机上开启全局代理。

### 卸载

```bash
# 方法一：一键卸载
curl -fsSL https://raw.githubusercontent.com/Last2334/onekey-p-linux/main/install.sh | sudo bash -s uninstall

# 方法二：使用已下载的脚本
sudo ./install.sh uninstall

# 方法三：使用 prox 命令
sudo prox  # 选择卸载选项
```

## 使用示例

### 使用 prox 管理命令（推荐）

安装完成后，可以使用 `prox` 命令进行管理：

```bash
sudo prox
```

提供以下功能：
- 启动/停止/重启服务
- 查看服务状态和日志
- 编辑配置文件
- 重新安装
- 卸载

### 基本安装（无认证）

```bash
sudo ./install.sh
# 选择下载源: 2 (推荐 ghproxy.com)
# 输入示例：
# SOCKS5 服务器地址: 127.0.0.1
# SOCKS5 端口: 1080
# 是否需要认证: n
```

### 带认证的安装

```bash
sudo ./install.sh
# 选择下载源: 2 (推荐 ghproxy.com)
# 输入示例：
# SOCKS5 服务器地址: proxy.example.com
# SOCKS5 端口: 1080
# 是否需要认证: y
# 用户名: myuser
# 密码: mypassword
```

## 常用命令

### 使用 prox 管理（推荐）

```bash
# 打开管理菜单
sudo prox
```

### 使用 systemctl 管理

```bash
# 查看服务状态
systemctl status sing-box

# 查看实时日志
journalctl -u sing-box -f

# 重启服务
systemctl restart sing-box

# 停止服务
systemctl stop sing-box

# 启动服务
systemctl start sing-box

# 编辑配置文件
nano /etc/sing-box/config.json

# 修改配置后重启服务
systemctl restart sing-box
```

## 配置说明

配置文件位置：`/etc/sing-box/config.json`

### 分流规则

- 国内网站和 IP：直连
- 私有 IP：直连
- 其他流量：通过代理

### DNS 配置

- 国内域名：使用阿里 DNS（223.5.5.5）
- 国外域名：使用 Google DNS（8.8.8.8）

## 故障排查

### 服务无法启动

```bash
# 查看详细日志
journalctl -u sing-box -n 50

# 检查配置文件语法
sing-box check -c /etc/sing-box/config.json
```

### 网络无法连接

1. 检查 SOCKS5 代理是否可用
2. 确认防火墙规则
3. 查看服务日志

### 部分网站无法访问

可能是分流规则问题，可以修改配置文件中的路由规则。

## 高级配置

如需自定义配置，可以编辑 `/etc/sing-box/config.json`：

```bash
# 编辑配置
nano /etc/sing-box/config.json

# 重启服务使配置生效
systemctl restart sing-box
```

## 注意事项

- 需要 root 权限运行
- 如果无法访问 GitHub，请先在主机上开启全局代理
- 安装过程中可选择国内镜像源下载 sing-box
- 确保 SOCKS5 代理服务器可访问
- 首次安装需要下载约 10-20MB 文件
- 卸载会删除所有配置文件

## 文件位置

- 二进制文件：`/usr/local/bin/sing-box`
- 配置文件：`/etc/sing-box/config.json`
- 服务文件：`/etc/systemd/system/sing-box.service`

## 许可证

MIT License
