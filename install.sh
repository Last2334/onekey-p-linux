#!/bin/bash

# sing-box 全局 TUN 一键部署脚本
# 支持安装和卸载

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

INSTALL_DIR="/usr/local/bin"
CONFIG_DIR="/etc/sing-box"
CONFIG_FILE="$CONFIG_DIR/config.json"
CACHE_FILE="$CONFIG_DIR/cache.db"
SERVICE_FILE="/etc/systemd/system/sing-box.service"
PROX_CMD="/usr/local/bin/prox"
DEFAULT_VERSION="1.13.8"
DEFAULT_SOCKS5_SERVER="192.168.200.1"
DEFAULT_SOCKS5_PORT="44444"
TTY_AVAILABLE=0
GITHUB_API_URL="https://api.github.com/repos/SagerNet/sing-box/releases/latest"

print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

init_tty() {
    if exec 3</dev/tty 4>/dev/tty 2>/dev/null; then
        TTY_AVAILABLE=1
    else
        TTY_AVAILABLE=0
    fi
}

read_prompt() {
    local __var_name="$1"
    local prompt="$2"
    local default_value=""
    local value=""

    if [ $# -ge 3 ]; then
        default_value="$3"
    fi

    if [ "$TTY_AVAILABLE" -eq 1 ]; then
        printf '%s' "$prompt" >&4
        IFS= read -r value <&3 || true
    else
        if [ -t 0 ]; then
            read -r -p "$prompt" value || true
        else
            print_error "当前运行方式无法进行交互输入，请下载脚本后执行: curl -O https://raw.githubusercontent.com/Last2334/onekey-p-linux/main/install.sh && sudo bash install.sh"
            exit 1
        fi
    fi

    if [ $# -ge 3 ] && [ -z "$value" ]; then
        value="$default_value"
    fi

    printf -v "$__var_name" '%s' "$value"
}

read_secret_prompt() {
    local __var_name="$1"
    local prompt="$2"
    local value=""

    if [ "$TTY_AVAILABLE" -eq 1 ]; then
        printf '%s' "$prompt" >&4
        IFS= read -r -s -u 3 value || true
        printf '\n' >&4
    else
        if [ -t 0 ]; then
            read -r -s -p "$prompt" value || true
            echo ""
        else
            print_error "当前运行方式无法进行交互输入，请下载脚本后执行: curl -O https://raw.githubusercontent.com/Last2334/onekey-p-linux/main/install.sh && sudo bash install.sh"
            exit 1
        fi
    fi

    printf -v "$__var_name" '%s' "$value"
}

pause_prompt() {
    local prompt="${1:-按回车键继续...}"
    local _

    if [ "$TTY_AVAILABLE" -eq 1 ]; then
        printf '%s' "$prompt" >&4
        IFS= read -r _ <&3 || true
    else
        if [ -t 0 ]; then
            read -r -p "$prompt" _ || true
        fi
    fi
}

check_root() {
    if [ "$EUID" -ne 0 ]; then
        print_error "请使用 root 权限运行此脚本"
        exit 1
    fi
}

check_requirements() {
    local cmd
    for cmd in curl tar mktemp systemctl; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            print_error "缺少依赖命令: $cmd"
            exit 1
        fi
    done
}

json_escape() {
    local value="$1"
    value=${value//\\/\\\\}
    value=${value//\"/\\\"}
    value=${value//$'\n'/\\n}
    value=${value//$'\r'/\\r}
    value=${value//$'\t'/\\t}
    printf '%s' "$value"
}

validate_port() {
    local port="$1"

    if ! [[ "$port" =~ ^[0-9]+$ ]]; then
        return 1
    fi

    if [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
        return 1
    fi

    return 0
}

format_proxy_host_for_url() {
    local host="$1"

    if [[ "$host" == *:* && "$host" != \[*\] ]]; then
        printf '[%s]' "$host"
    else
        printf '%s' "$host"
    fi
}

detect_arch() {
    local arch
    arch=$(uname -m)

    case "$arch" in
        x86_64)
            echo "amd64"
            ;;
        aarch64)
            echo "arm64"
            ;;
        armv7l)
            echo "armv7"
            ;;
        *)
            print_error "不支持的架构: $arch"
            exit 1
            ;;
    esac
}

get_latest_version() {
    local latest_version=""

    latest_version=$(curl -fsSL "$GITHUB_API_URL" 2>/dev/null | grep -m1 '"tag_name"' | sed -E 's/.*"tag_name"[[:space:]]*:[[:space:]]*"v?([^"]+)".*/\1/')

    if [ -z "$latest_version" ]; then
        print_warning "无法自动获取版本，使用默认稳定版本 $DEFAULT_VERSION" >&2
        latest_version="$DEFAULT_VERSION"
    fi

    printf '%s' "$latest_version"
}

download_and_install_singbox() {
    local arch="$1"
    local version="$2"
    local download_url
    local tmp_dir
    local extracted_dir
    local -a curl_download_args

    download_url="https://github.com/SagerNet/sing-box/releases/download/v${version}/sing-box-${version}-linux-${arch}.tar.gz"

    print_info "下载 sing-box..."
    print_info "下载地址: $download_url"
    print_info "如果这里长时间无进度，通常表示当前机器无法直连 GitHub"

    tmp_dir=$(mktemp -d)
    trap 'rm -rf "$tmp_dir"' RETURN

    curl_download_args=(
        curl
        -fL
        --progress-bar
        --connect-timeout 15
        --max-time 600
        --retry 3
        --retry-delay 2
        -o "$tmp_dir/sing-box.tar.gz"
        "$download_url"
    )

    if ! "${curl_download_args[@]}"; then
        print_error "下载失败，请检查网络连接或确认当前机器可以直连 GitHub"
        exit 1
    fi

    print_info "解压文件..."
    tar -xzf "$tmp_dir/sing-box.tar.gz" -C "$tmp_dir"

    extracted_dir="$tmp_dir/sing-box-${version}-linux-${arch}"
    if [ ! -f "$extracted_dir/sing-box" ]; then
        print_error "下载内容异常，未找到 sing-box 可执行文件"
        exit 1
    fi

    install -m 0755 "$extracted_dir/sing-box" "$INSTALL_DIR/sing-box"
    trap - RETURN
    rm -rf "$tmp_dir"

    print_info "sing-box 安装完成"
    "$INSTALL_DIR/sing-box" version
}

install_singbox() {
    local arch
    local latest_version

    print_info "开始安装 sing-box..."

    arch=$(detect_arch)
    print_info "使用 GitHub 官方源下载 sing-box..."
    print_info "获取最新版本信息..."
    latest_version=$(get_latest_version)

    print_info "版本: v$latest_version"
    download_and_install_singbox "$arch" "$latest_version"
}

create_config() {
    local socks5_server="$1"
    local socks5_port="$2"
    local socks5_user="$3"
    local socks5_pass="$4"
    local escaped_server
    local escaped_user
    local escaped_pass
    local auth_block=""

    print_info "创建配置文件..."

    mkdir -p "$CONFIG_DIR"

    escaped_server=$(json_escape "$socks5_server")
    escaped_user=$(json_escape "$socks5_user")
    escaped_pass=$(json_escape "$socks5_pass")

    if [ -n "$socks5_user" ] || [ -n "$socks5_pass" ]; then
        auth_block=$(cat <<EOF
      "username": "$escaped_user",
      "password": "$escaped_pass",
EOF
)
    fi

    cat > "$CONFIG_FILE" <<EOF
{
  "log": {
    "level": "info",
    "timestamp": true
  },
  "dns": {
    "servers": [
      {
        "type": "udp",
        "tag": "dns-local",
        "server": "223.5.5.5",
        "server_port": 53,
        "detour": "direct"
      },
      {
        "type": "https",
        "tag": "dns-remote",
        "server": "dns.google",
        "server_port": 443,
        "path": "/dns-query",
        "domain_resolver": "dns-local",
        "detour": "proxy"
      }
    ],
    "rules": [
      {
        "rule_set": "geosite-cn",
        "action": "route",
        "server": "dns-local"
      },
      {
        "domain_suffix": [
          ".lan",
          ".local"
        ],
        "action": "route",
        "server": "dns-local"
      }
    ],
    "final": "dns-remote",
    "strategy": "prefer_ipv4",
    "reverse_mapping": true
  },
  "inbounds": [
    {
      "type": "tun",
      "tag": "tun-in",
      "interface_name": "tun0",
      "address": [
        "172.19.0.1/30",
        "fdfe:dcba:9876::1/126"
      ],
      "auto_route": true,
      "strict_route": true,
      "stack": "system"
    }
  ],
  "outbounds": [
    {
      "type": "socks",
      "tag": "proxy",
      "server": "$escaped_server",
      "server_port": $socks5_port,
$auth_block      "domain_resolver": "dns-local"
    },
    {
      "type": "direct",
      "tag": "direct"
    }
  ],
  "route": {
    "rules": [
      {
        "inbound": "tun-in",
        "action": "sniff"
      },
      {
        "inbound": "tun-in",
        "protocol": "dns",
        "action": "hijack-dns"
      },
      {
        "inbound": "tun-in",
        "network": "icmp",
        "action": "route",
        "outbound": "direct"
      },
      {
        "inbound": "tun-in",
        "ip_is_private": true,
        "action": "route",
        "outbound": "direct"
      },
      {
        "inbound": "tun-in",
        "rule_set": [
          "geosite-cn",
          "geoip-cn"
        ],
        "action": "route",
        "outbound": "direct"
      }
    ],
    "rule_set": [
      {
        "tag": "geosite-cn",
        "type": "remote",
        "format": "binary",
        "url": "https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/geosite-cn.srs",
        "download_detour": "proxy",
        "update_interval": "24h"
      },
      {
        "tag": "geoip-cn",
        "type": "remote",
        "format": "binary",
        "url": "https://raw.githubusercontent.com/SagerNet/sing-geoip/rule-set/geoip-cn.srs",
        "download_detour": "proxy",
        "update_interval": "24h"
      }
    ],
    "auto_detect_interface": true,
    "default_domain_resolver": "dns-local",
    "final": "proxy"
  },
  "experimental": {
    "cache_file": {
      "enabled": true,
      "path": "$CACHE_FILE"
    }
  }
}
EOF

    print_info "配置文件创建完成: $CONFIG_FILE"
}

verify_socks5() {
    local socks5_server="$1"
    local socks5_port="$2"
    local socks5_user="$3"
    local socks5_pass="$4"
    local proxy_host
    local proxy_url
    local -a curl_args

    print_info "验证 SOCKS5 代理连接..."

    if ! command -v curl >/dev/null 2>&1; then
        print_warning "未安装 curl，跳过代理验证"
        return 0
    fi

    proxy_host=$(format_proxy_host_for_url "$socks5_server")
    proxy_url="socks5h://${proxy_host}:${socks5_port}"
    curl_args=(curl -fsS --connect-timeout 10 --max-time 20 --proxy "$proxy_url")

    if [ -n "$socks5_user" ] || [ -n "$socks5_pass" ]; then
        curl_args+=(--proxy-user "${socks5_user}:${socks5_pass}")
    fi

    if "${curl_args[@]}" https://www.gstatic.com/generate_204 >/dev/null 2>&1; then
        print_info "SOCKS5 代理验证成功"
        return 0
    fi

    print_warning "SOCKS5 代理验证失败，但仍可继续安装"
    print_warning "请确保代理信息正确，否则 sing-box 可能无法联网"
    read_prompt CONTINUE "是否继续安装? (y/n) [y]: " "y"

    if [[ "$CONTINUE" != "y" && "$CONTINUE" != "Y" ]]; then
        print_info "取消安装"
        exit 0
    fi

    return 0
}

validate_config() {
    print_info "校验 sing-box 配置..."

    if ! "$INSTALL_DIR/sing-box" check -c "$CONFIG_FILE"; then
        print_error "配置校验失败，请检查 $CONFIG_FILE"
        exit 1
    fi

    print_info "配置校验通过"
}

create_service() {
    print_info "创建 systemd 服务..."

    cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=sing-box service
Documentation=https://sing-box.sagernet.org
After=network-online.target nss-lookup.target
Wants=network-online.target

[Service]
Type=simple
ExecStartPre=$INSTALL_DIR/sing-box check -c $CONFIG_FILE
ExecStart=$INSTALL_DIR/sing-box run -c $CONFIG_FILE
Restart=on-failure
RestartSec=5s
LimitNOFILE=infinity

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    print_info "systemd 服务创建完成"
}

start_service() {
    print_info "启动 sing-box 服务..."

    if ! systemctl enable sing-box >/dev/null; then
        print_error "启用 sing-box 开机自启失败"
        exit 1
    fi

    if ! systemctl restart sing-box; then
        print_error "sing-box 服务启动失败"
        print_info "查看日志: journalctl -u sing-box -n 50 --no-pager"
        exit 1
    fi

    sleep 2

    if systemctl is-active --quiet sing-box; then
        print_info "sing-box 服务启动成功"
    else
        print_error "sing-box 服务启动失败"
        print_info "查看日志: journalctl -u sing-box -n 50 --no-pager"
        exit 1
    fi
}

create_prox_command() {
    print_info "创建 prox 管理命令..."

    cat > "$PROX_CMD" <<'EOF'
#!/bin/bash

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

INSTALL_DIR="/usr/local/bin"
CONFIG_DIR="/etc/sing-box"
CONFIG_FILE="$CONFIG_DIR/config.json"
CACHE_FILE="$CONFIG_DIR/cache.db"
SERVICE_FILE="/etc/systemd/system/sing-box.service"
PROX_CMD="/usr/local/bin/prox"
DEFAULT_VERSION="1.13.8"
TTY_AVAILABLE=0
GITHUB_API_URL="https://api.github.com/repos/SagerNet/sing-box/releases/latest"

print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

init_tty() {
    if exec 3</dev/tty 4>/dev/tty 2>/dev/null; then
        TTY_AVAILABLE=1
    else
        TTY_AVAILABLE=0
    fi
}

read_prompt() {
    local __var_name="$1"
    local prompt="$2"
    local default_value=""
    local value=""

    if [ $# -ge 3 ]; then
        default_value="$3"
    fi

    if [ "$TTY_AVAILABLE" -eq 1 ]; then
        printf '%s' "$prompt" >&4
        IFS= read -r value <&3 || true
    else
        if [ -t 0 ]; then
            read -r -p "$prompt" value || true
        else
            print_error "当前终端不可交互，请直接在 SSH 终端运行 sudo prox"
            exit 1
        fi
    fi

    if [ $# -ge 3 ] && [ -z "$value" ]; then
        value="$default_value"
    fi

    printf -v "$__var_name" '%s' "$value"
}

pause_prompt() {
    local prompt="${1:-按回车键继续...}"
    local _

    if [ "$TTY_AVAILABLE" -eq 1 ]; then
        printf '%s' "$prompt" >&4
        IFS= read -r _ <&3 || true
    else
        if [ -t 0 ]; then
            read -r -p "$prompt" _ || true
        fi
    fi
}

check_root() {
    if [ "$EUID" -ne 0 ]; then
        print_error "请使用 root 权限运行: sudo prox"
        exit 1
    fi
}

detect_arch() {
    case "$(uname -m)" in
        x86_64) echo "amd64" ;;
        aarch64) echo "arm64" ;;
        armv7l) echo "armv7" ;;
        *)
            print_error "不支持的架构: $(uname -m)"
            exit 1
            ;;
    esac
}

get_latest_version() {
    local latest_version

    latest_version=$(curl -fsSL "$GITHUB_API_URL" 2>/dev/null | grep -m1 '"tag_name"' | sed -E 's/.*"tag_name"[[:space:]]*:[[:space:]]*"v?([^"]+)".*/\1/')
    if [ -z "$latest_version" ]; then
        latest_version="$DEFAULT_VERSION"
        print_warning "无法自动获取版本，使用默认稳定版本 $latest_version" >&2
    fi

    printf '%s' "$latest_version"
}

install_binary() {
    local arch="$1"
    local version="$2"
    local download_url
    local tmp_dir
    local extracted_dir

    download_url="https://github.com/SagerNet/sing-box/releases/download/v${version}/sing-box-${version}-linux-${arch}.tar.gz"
    tmp_dir=$(mktemp -d)
    trap 'rm -rf "$tmp_dir"' RETURN

    print_info "下载 sing-box v$version ..."
    if ! curl -fL --retry 3 --retry-delay 2 -o "$tmp_dir/sing-box.tar.gz" "$download_url"; then
        print_error "下载失败，请检查网络连接"
        exit 1
    fi

    tar -xzf "$tmp_dir/sing-box.tar.gz" -C "$tmp_dir"
    extracted_dir="$tmp_dir/sing-box-${version}-linux-${arch}"

    if [ ! -f "$extracted_dir/sing-box" ]; then
        print_error "下载内容异常，未找到 sing-box 可执行文件"
        exit 1
    fi

    install -m 0755 "$extracted_dir/sing-box" "$INSTALL_DIR/sing-box"
    trap - RETURN
    rm -rf "$tmp_dir"
}

validate_config() {
    if [ ! -f "$CONFIG_FILE" ]; then
        print_error "配置文件不存在: $CONFIG_FILE"
        exit 1
    fi

    print_info "校验配置..."
    "$INSTALL_DIR/sing-box" check -c "$CONFIG_FILE"
}

pick_editor() {
    if [ -n "${EDITOR:-}" ] && command -v "$EDITOR" >/dev/null 2>&1; then
        printf '%s' "$EDITOR"
        return
    fi

    if command -v nano >/dev/null 2>&1; then
        printf '%s' "nano"
        return
    fi

    if command -v vim >/dev/null 2>&1; then
        printf '%s' "vim"
        return
    fi

    if command -v vi >/dev/null 2>&1; then
        printf '%s' "vi"
        return
    fi

    print_error "未找到可用编辑器，请设置 EDITOR 环境变量后重试"
    exit 1
}

show_status() {
    echo ""
    echo "========================================="
    echo "  sing-box 状态信息"
    echo "========================================="

    if systemctl is-active --quiet sing-box; then
        echo -e "服务状态: ${GREEN}运行中${NC}"
    else
        echo -e "服务状态: ${RED}已停止${NC}"
    fi

    if systemctl is-enabled --quiet sing-box 2>/dev/null; then
        echo -e "开机自启: ${GREEN}已启用${NC}"
    else
        echo -e "开机自启: ${RED}未启用${NC}"
    fi

    if [ -f "$INSTALL_DIR/sing-box" ]; then
        echo -e "程序版本: ${GREEN}$("$INSTALL_DIR/sing-box" version | head -n 1)${NC}"
    else
        echo -e "程序版本: ${RED}未安装${NC}"
    fi

    if [ -f "$CONFIG_FILE" ]; then
        echo -e "配置文件: ${GREEN}$CONFIG_FILE${NC}"
    else
        echo -e "配置文件: ${RED}不存在${NC}"
    fi

    echo "========================================="
    echo ""
}

show_menu() {
    clear
    echo ""
    echo "========================================="
    echo "  sing-box 管理菜单"
    echo "========================================="
    show_status
    echo "1) 启动服务"
    echo "2) 停止服务"
    echo "3) 重启服务"
    echo "4) 查看状态"
    echo "5) 查看日志"
    echo "6) 编辑配置"
    echo "7) 重新安装 sing-box 二进制"
    echo "8) 卸载"
    echo "0) 退出"
    echo "========================================="
    echo ""
}

start_service() {
    print_info "启动 sing-box 服务..."
    if ! systemctl start sing-box; then
        print_error "服务启动失败"
        return
    fi

    sleep 1
    if systemctl is-active --quiet sing-box; then
        print_info "服务启动成功"
    else
        print_error "服务启动失败"
    fi
}

stop_service() {
    print_info "停止 sing-box 服务..."
    if ! systemctl stop sing-box; then
        print_error "服务停止失败"
        return
    fi

    sleep 1
    print_info "服务已停止"
}

restart_service() {
    print_info "重启 sing-box 服务..."
    validate_config

    if ! systemctl restart sing-box; then
        print_error "服务重启失败"
        return
    fi

    sleep 1
    if systemctl is-active --quiet sing-box; then
        print_info "服务重启成功"
    else
        print_error "服务重启失败"
    fi
}

view_status() {
    systemctl --no-pager --full status sing-box
}

view_logs() {
    print_info "查看实时日志 (按 Ctrl+C 退出)..."
    sleep 1
    journalctl -u sing-box -f
}

edit_config() {
    local editor

    if [ ! -f "$CONFIG_FILE" ]; then
        print_error "配置文件不存在"
        return
    fi

    editor=$(pick_editor)
    print_info "使用编辑器: $editor"
    "$editor" "$CONFIG_FILE"

    if "$INSTALL_DIR/sing-box" check -c "$CONFIG_FILE"; then
        print_info "配置校验通过"
    else
        print_warning "配置校验失败，服务不会自动重启"
        pause_prompt
        return
    fi

    read_prompt RESTART "是否重启服务使配置生效? (y/n) [y]: " "y"
    if [[ "$RESTART" == "y" || "$RESTART" == "Y" ]]; then
        restart_service
    fi
}

reinstall() {
    local arch
    local latest_version

    if [ ! -f "$CONFIG_FILE" ]; then
        print_error "未找到现有配置文件，无法执行保留配置的重装"
        return
    fi

    print_warning "该操作只会重新安装 sing-box 二进制，并保留当前配置"
    read_prompt CONFIRM "确认继续? (y/n) [n]: " "n"

    if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
        print_info "取消重新安装"
        return
    fi

    arch=$(detect_arch)
    print_info "使用 GitHub 官方源下载 sing-box..."
    print_info "获取最新版本信息..."
    latest_version=$(get_latest_version)
    install_binary "$arch" "$latest_version"
    validate_config
    systemctl daemon-reload
    if ! systemctl restart sing-box; then
        print_error "重新安装后服务启动失败，请检查日志"
        return
    fi
    print_info "重新安装完成，当前版本:"
    "$INSTALL_DIR/sing-box" version
}

uninstall_local() {
    if systemctl is-active --quiet sing-box; then
        systemctl stop sing-box
    fi

    if systemctl is-enabled --quiet sing-box 2>/dev/null; then
        systemctl disable sing-box >/dev/null
    fi

    if [ -f "$SERVICE_FILE" ]; then
        rm -f "$SERVICE_FILE"
        systemctl daemon-reload
    fi

    rm -rf "$CONFIG_DIR"
    rm -f "$INSTALL_DIR/sing-box"
    rm -f "$PROX_CMD"
}

uninstall() {
    print_warning "卸载将删除 sing-box、配置文件、缓存和管理命令"
    read_prompt CONFIRM "确认卸载? (y/n) [n]: " "n"

    if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
        print_info "取消卸载"
        return
    fi

    uninstall_local
    print_info "卸载完成"
}

main() {
    check_root
    init_tty

    while true; do
        show_menu
        read_prompt choice "请选择操作 [0-8]: "

        case "$choice" in
            1)
                start_service
                pause_prompt
                ;;
            2)
                stop_service
                pause_prompt
                ;;
            3)
                restart_service
                pause_prompt
                ;;
            4)
                view_status
                pause_prompt
                ;;
            5)
                view_logs
                ;;
            6)
                edit_config
                pause_prompt
                ;;
            7)
                reinstall
                pause_prompt
                ;;
            8)
                uninstall
                exit 0
                ;;
            0)
                print_info "退出管理菜单"
                exit 0
                ;;
            *)
                print_error "无效的选择"
                sleep 1
                ;;
        esac
    done
}

main
EOF

    chmod +x "$PROX_CMD"
    print_info "prox 命令创建完成"
}

uninstall() {
    print_warning "开始卸载 sing-box..."

    if systemctl is-active --quiet sing-box; then
        print_info "停止 sing-box 服务..."
        systemctl stop sing-box
    fi

    if systemctl is-enabled --quiet sing-box 2>/dev/null; then
        print_info "禁用 sing-box 服务..."
        systemctl disable sing-box >/dev/null
    fi

    if [ -f "$SERVICE_FILE" ]; then
        print_info "删除服务文件..."
        rm -f "$SERVICE_FILE"
        systemctl daemon-reload
    fi

    if [ -d "$CONFIG_DIR" ]; then
        print_info "删除配置文件和缓存..."
        rm -rf "$CONFIG_DIR"
    fi

    if [ -f "$INSTALL_DIR/sing-box" ]; then
        print_info "删除 sing-box 二进制文件..."
        rm -f "$INSTALL_DIR/sing-box"
    fi

    if [ -f "$PROX_CMD" ]; then
        print_info "删除 prox 命令..."
        rm -f "$PROX_CMD"
    fi

    print_info "sing-box 卸载完成"
}

install() {
    local socks5_server
    local socks5_port
    local need_auth
    local socks5_user=""
    local socks5_pass=""

    echo ""
    echo "========================================="
    echo "  sing-box 全局 TUN 一键部署脚本"
    echo "========================================="
    echo ""

    read_prompt socks5_server "请输入 SOCKS5 服务器地址 [$DEFAULT_SOCKS5_SERVER]: " "$DEFAULT_SOCKS5_SERVER"
    if [ -z "$socks5_server" ]; then
        print_error "SOCKS5 服务器地址不能为空"
        exit 1
    fi

    read_prompt socks5_port "请输入 SOCKS5 端口 [$DEFAULT_SOCKS5_PORT]: " "$DEFAULT_SOCKS5_PORT"

    if ! validate_port "$socks5_port"; then
        print_error "SOCKS5 端口无效: $socks5_port"
        exit 1
    fi

    read_prompt need_auth "是否需要认证? (y/n) [n]: " "n"

    if [[ "$need_auth" == "y" || "$need_auth" == "Y" ]]; then
        read_prompt socks5_user "请输入用户名: "
        read_secret_prompt socks5_pass "请输入密码: "

        if [ -z "$socks5_user" ] || [ -z "$socks5_pass" ]; then
            print_error "已启用认证时，用户名和密码都不能为空"
            exit 1
        fi
    fi

    verify_socks5 "$socks5_server" "$socks5_port" "$socks5_user" "$socks5_pass"

    if [ -f "$INSTALL_DIR/sing-box" ]; then
        print_warning "检测到已安装 sing-box"
        read_prompt REINSTALL "是否重新安装 sing-box 二进制? (y/n) [n]: " "n"
        if [[ "$REINSTALL" == "y" || "$REINSTALL" == "Y" ]]; then
            install_singbox
        else
            print_info "跳过二进制安装，保留现有版本"
        fi
    else
        install_singbox
    fi

    create_config "$socks5_server" "$socks5_port" "$socks5_user" "$socks5_pass"
    validate_config
    create_service
    start_service
    create_prox_command

    echo ""
    print_info "========================================="
    print_info "安装完成！"
    print_info "========================================="
    print_info "快速管理命令: sudo prox"
    print_info "配置文件: $CONFIG_FILE"
    print_info "缓存文件: $CACHE_FILE"
    print_info "查看状态: systemctl status sing-box"
    print_info "查看日志: journalctl -u sing-box -f"
    print_info "配置校验: sing-box check -c $CONFIG_FILE"
    print_info "========================================="
    echo ""
}

main() {
    check_root
    check_requirements
    init_tty

    if [ "$1" == "uninstall" ]; then
        uninstall
    else
        install
    fi
}

main "$@"
