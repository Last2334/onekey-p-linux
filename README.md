# sing-box Linux 全局 TUN 一键部署脚本

这是一个用于 Linux 的 `sing-box` 一键安装脚本。现在的一键入口会先安装 `prox` 管理命令，再进入 `prox` 菜单，由 `prox` 负责安装、卸载和修改透明代理。

运行脚本后会先显示当前脚本版本，便于确认你拿到的是不是最新发布内容。

## 功能特点

- 一键安装 `prox` 管理命令并自动进入管理菜单
- 通过 `prox` 安装并自动下载最新稳定版 `sing-box`
- 仅使用 GitHub 官方源下载 `sing-box`
- 安装前自动验证 SOCKS5 代理连通性
- 验证成功后显示代理出口 IP 和国家
- 自动生成 TUN 全局代理配置
- 使用官方 `rule-set` 实现国内直连、其他流量走代理
- 自动创建 `systemd` 服务并开机自启
- 提供 `sudo prox` 管理菜单
- 支持本地卸载和保留配置的二进制重装

## 系统要求

- Linux 系统
- `systemd`
- Root 权限
- 常见基础工具：`curl`、`tar`、`mktemp`

支持架构：

- `x86_64`
- `aarch64`
- `armv7l`

## 快速开始

### 一键安装

```bash
curl -fsSL https://raw.githubusercontent.com/Last2334/onekey-p-linux/main/quick-install.sh | sudo bash
```

说明：

- 上面的命令调用的是一个很薄的引导脚本
- 引导脚本会先下载最新 `install.sh`
- 然后把 `prox` 和本地 `install.sh` 安装到系统里
- 安装完成后自动进入 `prox` 菜单

如果你想手动检查脚本内容，也可以先下载再执行：

```bash
curl -O https://raw.githubusercontent.com/Last2334/onekey-p-linux/main/install.sh
chmod +x install.sh
sudo ./install.sh bootstrap-prox
```

进入 `prox` 后，先选择“安装/更新透明代理”，安装过程会提示：

1. 输入 SOCKS5 服务器地址，默认 `192.168.200.1`
2. 输入 SOCKS5 端口，默认 `44444`
3. 选择是否启用认证
4. 在需要时输入用户名和密码
5. 执行代理连通性验证，并显示出口 IP / 国家

之后你可以随时使用：

```bash
sudo prox
```

如果你重复执行安装脚本，脚本会默认保留现有配置文件，避免无提示覆盖手工修改过的内容。

## 配置说明

脚本会生成：

- 配置文件：`/etc/sing-box/config.json`
- 缓存文件：`/etc/sing-box/cache.db`
- 服务文件：`/etc/systemd/system/sing-box.service`
- 管理命令：`/usr/local/bin/prox`
- 本地安装脚本：`/usr/local/lib/onekey-p-linux/install.sh`

配置默认行为：

- TUN 全局代理
- 中国大陆相关流量直连
- 私有地址直连
- 其他流量走 SOCKS5 代理
- DNS 查询劫持到 sing-box

说明：

- 配置使用官方推荐的 `rule-set` 方式，不再依赖已废弃的 `geosite` / `geoip` 旧写法
- 首次启动时，`sing-box` 会通过代理下载官方 `rule-set` 文件，首次启动可能稍慢
- 如果你的 SOCKS5 服务器使用域名，建议本机能正常解析该域名，或直接填写 IP

## 下载说明

脚本只使用 GitHub 官方源：

- 版本查询：GitHub Releases API
- 二进制下载：GitHub Releases 官方下载地址
- 访问 GitHub 时默认复用你输入的 SOCKS5 代理

如果最新版本信息无法获取，脚本会回退到内置稳定版本。

## 管理命令

### 推荐方式

```bash
sudo prox
```

菜单支持：

- 安装/更新透明代理
- 启动服务
- 停止服务
- 重启服务
- 查看状态
- 查看日志
- 修改透明代理配置
- 重新安装 `sing-box` 二进制
- 检查透明代理是否激活
- 完整卸载 `prox + sing-box`

注意：

- 菜单里的“安装/更新透明代理”会进入正式安装流程
- 菜单里的“重新安装”只会更新 `sing-box` 二进制，保留现有配置文件
- 菜单里的“检查透明代理是否激活”会检查服务状态、`tun0`、公网路由和当前公网出口 IP
- 菜单里的“完整卸载”会删除 `prox`、`sing-box`、配置文件、缓存和 systemd 服务

### 更新服务器上的 prox

在服务器上重新执行快速安装命令即可更新 `prox` 管理命令和本地安装脚本：

```bash
curl -fsSL https://raw.githubusercontent.com/Last2334/onekey-p-linux/main/quick-install.sh | sudo bash
```

该操作会刷新：

- `/usr/local/bin/prox`
- `/usr/local/lib/onekey-p-linux/install.sh`

不会删除现有 `/etc/sing-box/config.json`。如果只想更新 `sing-box` 二进制，进入 `sudo prox` 后选择“重新安装 sing-box 二进制”。

### 使用 systemd

```bash
systemctl status sing-box
systemctl restart sing-box
systemctl stop sing-box
systemctl start sing-box
journalctl -u sing-box -f
```

### 校验配置

```bash
sing-box check -c /etc/sing-box/config.json
```

## 卸载

### 使用当前脚本

```bash
sudo ./install.sh uninstall
```

### 使用管理菜单

```bash
sudo prox
```

通过 `sudo prox` 的“完整卸载 prox + sing-box”执行卸载时，会删除：

- `prox` 管理命令
- `sing-box` 二进制
- 配置文件和缓存
- `systemd` 服务文件
- 本地安装脚本

## 故障排查

### 服务无法启动

先看日志：

```bash
journalctl -u sing-box -n 50 --no-pager
```

再做配置校验：

```bash
sing-box check -c /etc/sing-box/config.json
```

### 代理验证失败但仍想继续安装

脚本现在允许在验证失败后继续安装。常见原因：

- SOCKS5 地址或端口填写错误
- 用户名密码错误
- 代理本身不可用
- 目标机器到代理服务器网络不通

如果继续安装后服务仍无法联网，请优先检查上面的代理参数。

### 首次启动较慢

首次启动需要下载 `rule-set` 文件，这是正常现象。可以结合日志确认下载是否成功：

```bash
journalctl -u sing-box -f
```

## 注意事项

- 需要使用 root 权限运行
- 脚本依赖 `systemd`，不适用于 OpenRC 等其他 init 系统
- 脚本默认以当前稳定版 `sing-box` 为目标配置格式
- 修改配置后建议先执行 `sing-box check`，再重启服务

## 许可证

MIT License
