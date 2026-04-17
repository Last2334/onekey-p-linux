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
SERVICE_FILE="/etc/systemd/system/sing-box.service"
PROX_CMD="/usr/local/bin/prox"

print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

check_root() {
    if [ "$EUID" -ne 0 ]; then
        print_error "请使用 root 权限运行此脚本"
        exit 1
    fi
}

install_singbox() {
    print_info "开始安装 sing-box..."
    
    # 检测系统架构
    ARCH=$(uname -m)
    case $ARCH in
        x86_64)
            ARCH="amd64"
            ;;
        aarch64)
            ARCH="arm64"
            ;;
        armv7l)
            ARCH="armv7"
            ;;
        *)
            print_error "不支持的架构: $ARCH"
            exit 1
            ;;
    esac
    
    # 选择下载源
    echo ""
    echo "请选择下载源:"
    echo "1) GitHub 官方源（国外）"
    echo "2) ghproxy.com 镜像（推荐）"
    echo "3) ghps.cc 镜像"
    echo "4) gh-proxy.com 镜像"
    read -p "请选择 [2]: " MIRROR_CHOICE
    MIRROR_CHOICE=${MIRROR_CHOICE:-2}
    
    case $MIRROR_CHOICE in
        1)
            MIRROR_PREFIX=""
            API_URL="https://api.github.com/repos/SagerNet/sing-box/releases/latest"
            ;;
        2)
            MIRROR_PREFIX="https://ghproxy.com/"
            API_URL="https://ghproxy.com/https://api.github.com/repos/SagerNet/sing-box/releases/latest"
            ;;
        3)
            MIRROR_PREFIX="https://ghps.cc/"
            API_URL="https://ghps.cc/https://api.github.com/repos/SagerNet/sing-box/releases/latest"
            ;;
        4)
            MIRROR_PREFIX="https://gh-proxy.com/"
            API_URL="https://gh-proxy.com/https://api.github.com/repos/SagerNet/sing-box/releases/latest"
            ;;
        *)
            print_error "无效的选择"
            exit 1
            ;;
    esac
    
    # 获取最新版本
    print_info "获取最新版本信息..."
    LATEST_VERSION=$(curl -s "$API_URL" | grep '"tag_name"' | sed -E 's/.*"v([^"]+)".*/\1/')
    
    if [ -z "$LATEST_VERSION" ]; then
        print_warning "无法自动获取版本，使用默认版本 1.9.0"
        LATEST_VERSION="1.9.0"
    fi
    
    print_info "版本: v$LATEST_VERSION"
    
    # 下载 sing-box
    DOWNLOAD_URL="${MIRROR_PREFIX}https://github.com/SagerNet/sing-box/releases/download/v${LATEST_VERSION}/sing-box-${LATEST_VERSION}-linux-${ARCH}.tar.gz"
    print_info "下载 sing-box..."
    print_info "下载地址: $DOWNLOAD_URL"
    
    TMP_DIR=$(mktemp -d)
    cd "$TMP_DIR"
    
    if ! curl -L -o sing-box.tar.gz "$DOWNLOAD_URL"; then
        print_error "下载失败，请检查网络连接或尝试其他镜像源"
        rm -rf "$TMP_DIR"
        exit 1
    fi
    
    # 解压并安装
    print_info "解压文件..."
    tar -xzf sing-box.tar.gz
    mv sing-box-${LATEST_VERSION}-linux-${ARCH}/sing-box "$INSTALL_DIR/"
    chmod +x "$INSTALL_DIR/sing-box"
    
    rm -rf "$TMP_DIR"
    print_info "sing-box 安装完成"
    
    # 显示版本信息
    "$INSTALL_DIR/sing-box" version
}

create_config() {
    local SOCKS5_SERVER=$1
    local SOCKS5_PORT=$2
    local SOCKS5_USER=$3
    local SOCKS5_PASS=$4
    
    print_info "创建配置文件..."
    
    mkdir -p "$CONFIG_DIR"
    
    # 构建 socks5 outbound 配置
    SOCKS5_CONFIG="{
      \"type\": \"socks\",
      \"tag\": \"proxy\",
      \"server\": \"$SOCKS5_SERVER\",
      \"server_port\": $SOCKS5_PORT"
    
    if [ -n "$SOCKS5_USER" ] && [ -n "$SOCKS5_PASS" ]; then
        SOCKS5_CONFIG="$SOCKS5_CONFIG,
      \"username\": \"$SOCKS5_USER\",
      \"password\": \"$SOCKS5_PASS\""
    fi
    
    SOCKS5_CONFIG="$SOCKS5_CONFIG
    }"
    
    cat > "$CONFIG_DIR/config.json" << EOF
{
  "log": {
    "level": "info",
    "timestamp": true
  },
  "dns": {
    "servers": [
      {
        "tag": "remote",
        "address": "tls://8.8.8.8"
      },
      {
        "tag": "local",
        "address": "223.5.5.5",
        "detour": "direct"
      }
    ],
    "rules": [
      {
        "outbound": "any",
        "server": "local"
      },
      {
        "clash_mode": "direct",
        "server": "local"
      },
      {
        "clash_mode": "global",
        "server": "remote"
      },
      {
        "geosite": "cn",
        "server": "local"
      }
    ]
  },
  "inbounds": [
    {
      "type": "tun",
      "tag": "tun-in",
      "interface_name": "tun0",
      "inet4_address": "172.19.0.1/30",
      "auto_route": true,
      "strict_route": true,
      "stack": "system",
      "sniff": true
    }
  ],
  "outbounds": [
    $SOCKS5_CONFIG,
    {
      "type": "direct",
      "tag": "direct"
    },
    {
      "type": "block",
      "tag": "block"
    },
    {
      "type": "dns",
      "tag": "dns-out"
    }
  ],
  "route": {
    "rules": [
      {
        "protocol": "dns",
        "outbound": "dns-out"
      },
      {
        "geosite": "cn",
        "geoip": ["private", "cn"],
        "outbound": "direct"
      }
    ],
    "final": "proxy",
    "auto_detect_interface": true
  }
}
EOF
    
    print_info "配置文件创建完成: $CONFIG_DIR/config.json"
}

create_service() {
    print_info "创建 systemd 服务..."
    
    cat > "$SERVICE_FILE" << EOF
[Unit]
Description=sing-box service
Documentation=https://sing-box.sagernet.org
After=network.target nss-lookup.target

[Service]
Type=simple
ExecStart=$INSTALL_DIR/sing-box run -c $CONFIG_DIR/config.json
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
    systemctl enable sing-box
    systemctl start sing-box
    
    sleep 2
    
    if systemctl is-active --quiet sing-box; then
        print_info "sing-box 服务启动成功"
    else
        print_error "sing-box 服务启动失败"
        print_info "查看日志: journalctl -u sing-box -f"
        exit 1
    fi
}

create_prox_command() {
    print_info "创建 prox 管理命令..."
    
    cat > "$PROX_CMD" << 'EOF'
#!/bin/bash

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
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
        echo -e "开机自启: ${RED}已禁用${NC}"
    fi
    
    if [ -f /etc/sing-box/config.json ]; then
        echo -e "配置文件: ${GREEN}存在${NC}"
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
    echo "7) 重新安装"
    echo "8) 卸载"
    echo "0) 退出"
    echo "========================================="
    echo ""
}

start_service() {
    print_info "启动 sing-box 服务..."
    systemctl start sing-box
    sleep 1
    if systemctl is-active --quiet sing-box; then
        print_info "服务启动成功"
    else
        print_error "服务启动失败"
    fi
}

stop_service() {
    print_info "停止 sing-box 服务..."
    systemctl stop sing-box
    sleep 1
    print_info "服务已停止"
}

restart_service() {
    print_info "重启 sing-box 服务..."
    systemctl restart sing-box
    sleep 1
    if systemctl is-active --quiet sing-box; then
        print_info "服务重启成功"
    else
        print_error "服务重启失败"
    fi
}

view_status() {
    systemctl status sing-box
}

view_logs() {
    print_info "查看实时日志 (按 Ctrl+C 退出)..."
    sleep 1
    journalctl -u sing-box -f
}

edit_config() {
    if [ ! -f /etc/sing-box/config.json ]; then
        print_error "配置文件不存在"
        return
    fi
    
    print_info "编辑配置文件..."
    ${EDITOR:-nano} /etc/sing-box/config.json
    
    read -p "是否重启服务使配置生效? (y/n) [y]: " RESTART
    RESTART=${RESTART:-y}
    
    if [[ "$RESTART" == "y" || "$RESTART" == "Y" ]]; then
        restart_service
    fi
}

reinstall() {
    print_warning "重新安装将保留当前配置"
    read -p "确认重新安装? (y/n) [n]: " CONFIRM
    
    if [[ "$CONFIRM" == "y" || "$CONFIRM" == "Y" ]]; then
        print_info "开始重新安装..."
        curl -fsSL https://raw.githubusercontent.com/Last2334/onekey-p-linux/main/install.sh | bash
    else
        print_info "取消重新安装"
    fi
}

uninstall() {
    print_warning "卸载将删除所有配置文件和服务"
    read -p "确认卸载? (y/n) [n]: " CONFIRM
    
    if [[ "$CONFIRM" == "y" || "$CONFIRM" == "Y" ]]; then
        print_info "开始卸载..."
        curl -fsSL https://raw.githubusercontent.com/Last2334/onekey-p-linux/main/install.sh | bash -s uninstall
        
        # 删除 prox 命令本身
        if [ -f /usr/local/bin/prox ]; then
            rm -f /usr/local/bin/prox
            print_info "prox 命令已删除"
        fi
    else
        print_info "取消卸载"
    fi
}

check_root() {
    if [ "$EUID" -ne 0 ]; then
        print_error "请使用 root 权限运行: sudo prox"
        exit 1
    fi
}

main() {
    check_root
    
    while true; do
        show_menu
        read -p "请选择操作 [0-8]: " choice
        
        case $choice in
            1)
                start_service
                read -p "按回车键继续..."
                ;;
            2)
                stop_service
                read -p "按回车键继续..."
                ;;
            3)
                restart_service
                read -p "按回车键继续..."
                ;;
            4)
                view_status
                read -p "按回车键继续..."
                ;;
            5)
                view_logs
                ;;
            6)
                edit_config
                read -p "按回车键继续..."
                ;;
            7)
                reinstall
                read -p "按回车键继续..."
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
    
    # 停止服务
    if systemctl is-active --quiet sing-box; then
        print_info "停止 sing-box 服务..."
        systemctl stop sing-box
    fi
    
    # 禁用服务
    if systemctl is-enabled --quiet sing-box 2>/dev/null; then
        print_info "禁用 sing-box 服务..."
        systemctl disable sing-box
    fi
    
    # 删除服务文件
    if [ -f "$SERVICE_FILE" ]; then
        print_info "删除服务文件..."
        rm -f "$SERVICE_FILE"
        systemctl daemon-reload
    fi
    
    # 删除配置文件
    if [ -d "$CONFIG_DIR" ]; then
        print_info "删除配置文件..."
        rm -rf "$CONFIG_DIR"
    fi
    
    # 删除二进制文件
    if [ -f "$INSTALL_DIR/sing-box" ]; then
        print_info "删除 sing-box 二进制文件..."
        rm -f "$INSTALL_DIR/sing-box"
    fi
    
    # 删除 prox 命令
    if [ -f "$PROX_CMD" ]; then
        print_info "删除 prox 命令..."
        rm -f "$PROX_CMD"
    fi
    
    print_info "sing-box 卸载完成"
}

install() {
    echo ""
    echo "========================================="
    echo "  sing-box 全局 TUN 一键部署脚本"
    echo "========================================="
    echo ""
    
    # 输入 SOCKS5 代理信息
    read -p "请输入 SOCKS5 服务器地址: " SOCKS5_SERVER
    read -p "请输入 SOCKS5 端口 [1080]: " SOCKS5_PORT
    SOCKS5_PORT=${SOCKS5_PORT:-1080}
    
    read -p "是否需要认证? (y/n) [n]: " NEED_AUTH
    NEED_AUTH=${NEED_AUTH:-n}
    
    SOCKS5_USER=""
    SOCKS5_PASS=""
    
    if [[ "$NEED_AUTH" == "y" || "$NEED_AUTH" == "Y" ]]; then
        read -p "请输入用户名: " SOCKS5_USER
        read -sp "请输入密码: " SOCKS5_PASS
        echo ""
    fi
    
    # 验证输入
    if [ -z "$SOCKS5_SERVER" ]; then
        print_error "SOCKS5 服务器地址不能为空"
        exit 1
    fi
    
    # 检查是否已安装
    if [ -f "$INSTALL_DIR/sing-box" ]; then
        print_warning "检测到已安装 sing-box"
        read -p "是否重新安装? (y/n) [n]: " REINSTALL
        if [[ "$REINSTALL" != "y" && "$REINSTALL" != "Y" ]]; then
            print_info "跳过安装步骤"
        else
            install_singbox
        fi
    else
        install_singbox
    fi
    
    # 创建配置
    create_config "$SOCKS5_SERVER" "$SOCKS5_PORT" "$SOCKS5_USER" "$SOCKS5_PASS"
    
    # 创建服务
    create_service
    
    # 启动服务
    start_service
    
    # 创建 prox 管理命令
    create_prox_command
    
    echo ""
    print_info "========================================="
    print_info "安装完成！"
    print_info "========================================="
    print_info "快速管理命令: sudo prox"
    print_info ""
    print_info "常用命令:"
    print_info "  管理菜单: sudo prox"
    print_info "  查看状态: systemctl status sing-box"
    print_info "  查看日志: journalctl -u sing-box -f"
    print_info "  重启服务: systemctl restart sing-box"
    print_info "  停止服务: systemctl stop sing-box"
    print_info "  配置文件: $CONFIG_DIR/config.json"
    print_info "========================================="
    echo ""
}

main() {
    check_root
    
    # 如果没有参数，显示菜单
    if [ -z "$1" ]; then
        echo ""
        echo "========================================="
        echo "  sing-box 全局 TUN 部署脚本"
        echo "========================================="
        echo ""
        echo "请选择操作:"
        echo "1) 安装 sing-box"
        echo "2) 卸载 sing-box"
        echo "0) 退出"
        echo ""
        read -p "请选择 [1]: " MENU_CHOICE
        MENU_CHOICE=${MENU_CHOICE:-1}
        
        case $MENU_CHOICE in
            1)
                install
                ;;
            2)
                uninstall
                ;;
            0)
                print_info "退出"
                exit 0
                ;;
            *)
                print_error "无效的选择"
                exit 1
                ;;
        esac
    elif [ "$1" == "uninstall" ]; then
        uninstall
    else
        install
    fi
}

main "$@"
