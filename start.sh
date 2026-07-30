#!/usr/bin/env bash
#
# Hysteria 2 一键启动链（四步合一）
# Repo: https://github.com/JasonZhangDad/install-hy2-script
#
# 1. 提权 root（等同 sudo -i）
# 2. 更新软件源 / 基础软件包
# 3. 拉取并执行 install-hy2.sh
# 4. 开放防火墙端口规则
#
# 用法（复制这一条即可）:
#   curl -fsSL https://raw.githubusercontent.com/JasonZhangDad/install-hy2-script/main/start.sh | sudo bash
#
# 一键安装（跳过菜单）:
#   curl -fsSL https://raw.githubusercontent.com/JasonZhangDad/install-hy2-script/main/start.sh | sudo bash -s -- onekey
#

set -euo pipefail

export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8
export DEBIAN_FRONTEND=noninteractive

REPO_RAW_START="https://raw.githubusercontent.com/JasonZhangDad/install-hy2-script/main/start.sh"
REPO_RAW_INSTALL="https://raw.githubusercontent.com/JasonZhangDad/install-hy2-script/main/install-hy2.sh"
HY_META="/etc/hysteria/install.meta"

# curl|bash 时把输入切到终端，保证后面菜单能交互
if [[ ! -t 0 ]]; then
  if { exec 3</dev/tty; } 2>/dev/null; then
    exec 0<&3
    exec 3<&-
  fi
fi

RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
PLAIN="\033[0m"
BOLD="\033[1m"

info()  { echo -e "${GREEN}[INFO]${PLAIN} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${PLAIN} $*"; }
err()   { echo -e "${RED}[ERROR]${PLAIN} $*" >&2; }
ok()    { echo -e "${GREEN}[OK]${PLAIN} $*"; }
step()  { echo -e "\n${GREEN}${BOLD}==> $*${PLAIN}"; }

die() { err "$*"; exit 1; }

# ========== 1. root（sudo -i 效果）==========
ensure_root() {
  step "步骤 1/4：检查 / 提权 root"
  local uid
  uid="${EUID:-$(id -u 2>/dev/null || echo 1)}"
  if [[ "$uid" -eq 0 ]]; then
    ok "已是 root (user=$(id -un) uid=0)"
    return 0
  fi

  if [[ "${HY2_START_REEXEC:-}" == "1" ]]; then
    die "sudo 提权失败，请手动: curl -fsSL ${REPO_RAW_START} | sudo bash"
  fi

  if ! command -v sudo >/dev/null 2>&1; then
    die "需要 root，且未找到 sudo。请: sudo -i 后再执行"
  fi

  warn "当前非 root，正在 sudo 提权重跑本脚本..."
  local tmp
  tmp="$(mktemp /tmp/hy2-start.XXXXXX.sh)"
  if command -v curl >/dev/null 2>&1 && curl -fsSL "$REPO_RAW_START" -o "$tmp" 2>/dev/null; then
    chmod 700 "$tmp"
    exec sudo -E env HY2_START_REEXEC=1 bash "$tmp" "$@"
  fi
  # 本地文件回退
  local src="${BASH_SOURCE[0]:-}"
  if [[ -n "$src" && -f "$src" && -r "$src" ]]; then
    exec sudo -E env HY2_START_REEXEC=1 bash "$src" "$@"
  fi
  die "无法提权。请执行: curl -fsSL ${REPO_RAW_START} | sudo bash"
}

# ========== 2. 更新软件源 / 软件包 ==========
detect_pkg() {
  if [[ -f /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    OS_ID="${ID:-}"
    OS_LIKE="${ID_LIKE:-}"
  else
    OS_ID=""
    OS_LIKE=""
  fi
  local s
  s="$(echo "${OS_ID} ${OS_LIKE}" | tr '[:upper:]' '[:lower:]')"
  if echo "$s" | grep -Eq 'debian|ubuntu'; then
    PKG_FAMILY="debian"
  elif echo "$s" | grep -Eq 'centos|rhel|rocky|alma|fedora|amazon|oracle|opencloud|anolis'; then
    PKG_FAMILY="rhel"
  elif echo "$s" | grep -Eq 'arch|manjaro'; then
    PKG_FAMILY="arch"
  else
    PKG_FAMILY="unknown"
  fi
}

update_packages() {
  step "步骤 2/4：更新软件源与基础软件包"
  detect_pkg
  info "系统包管理类型: ${PKG_FAMILY} (${PRETTY_NAME:-$OS_ID})"

  case "$PKG_FAMILY" in
    debian)
      apt-get update -y
      # 更新可安全升级的包（非交互）；失败不中断整条链
      apt-get upgrade -y || warn "apt upgrade 部分失败，继续..."
      apt-get install -y curl wget ca-certificates openssl socat cron \
        iptables iptables-persistent netfilter-persistent qrencode 2>/dev/null \
        || apt-get install -y curl wget ca-certificates openssl socat iptables || true
      ok "Debian/Ubuntu 软件源与基础包已更新"
      ;;
    rhel)
      if command -v dnf >/dev/null 2>&1; then
        dnf -y makecache || true
        dnf -y update || warn "dnf update 部分失败，继续..."
        dnf -y install curl wget ca-certificates openssl socat cronie iptables qrencode 2>/dev/null \
          || dnf -y install curl wget ca-certificates openssl socat iptables || true
      else
        yum -y makecache || true
        yum -y update || warn "yum update 部分失败，继续..."
        yum -y install curl wget ca-certificates openssl socat cronie iptables 2>/dev/null \
          || yum -y install curl wget ca-certificates openssl || true
      fi
      ok "RHEL 系软件源与基础包已更新"
      ;;
    arch)
      pacman -Sy --noconfirm
      pacman -S --noconfirm --needed curl wget ca-certificates openssl socat iptables qrencode 2>/dev/null || true
      ok "Arch 软件源与基础包已更新"
      ;;
    *)
      warn "未识别的系统，跳过自动更新；请确保已安装 curl"
      command -v curl >/dev/null 2>&1 || die "缺少 curl，请先手动安装"
      ;;
  esac
}

# ========== 4. 开放端口规则 ==========
detect_firewall() {
  if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -qiE 'Status:\s*active'; then
    echo "ufw"
  elif command -v firewall-cmd >/dev/null 2>&1 && { systemctl is-active --quiet firewalld 2>/dev/null || firewall-cmd --state 2>/dev/null | grep -qi running; }; then
    echo "firewalld"
  elif command -v iptables >/dev/null 2>&1; then
    echo "iptables"
  else
    echo "none"
  fi
}

persist_iptables() {
  if command -v netfilter-persistent >/dev/null 2>&1; then
    netfilter-persistent save >/dev/null 2>&1 && return 0
  fi
  if [[ -d /etc/sysconfig ]]; then
    iptables-save >/etc/sysconfig/iptables 2>/dev/null && return 0
  fi
  if [[ -d /etc/iptables ]]; then
    mkdir -p /etc/iptables
    iptables-save >/etc/iptables/rules.v4 2>/dev/null && return 0
  fi
  return 1
}

# 开放单个 TCP/UDP 端口
_fw_open() {
  local proto="$1" port="$2"
  local fw
  fw="$(detect_firewall)"
  case "$fw" in
    ufw)
      ufw allow "${port}/${proto}" >/dev/null 2>&1 || true
      ;;
    firewalld)
      firewall-cmd --permanent --add-port="${port}/${proto}" >/dev/null 2>&1 || true
      ;;
    iptables)
      iptables -D INPUT -p "$proto" --dport "$port" -j ACCEPT 2>/dev/null || true
      iptables -I INPUT -p "$proto" --dport "$port" -j ACCEPT 2>/dev/null || true
      ;;
  esac
}

_fw_open_range_udp() {
  local first="$1" last="$2"
  local fw
  fw="$(detect_firewall)"
  case "$fw" in
    ufw)
      ufw allow "${first}:${last}/udp" >/dev/null 2>&1 || true
      ;;
    firewalld)
      firewall-cmd --permanent --add-port="${first}-${last}/udp" >/dev/null 2>&1 || true
      ;;
    iptables)
      iptables -D INPUT -p udp --dport "${first}:${last}" -j ACCEPT 2>/dev/null || true
      iptables -I INPUT -p udp --dport "${first}:${last}" -j ACCEPT 2>/dev/null || true
      ;;
  esac
}

_fw_reload() {
  local fw
  fw="$(detect_firewall)"
  case "$fw" in
    ufw) ufw reload >/dev/null 2>&1 || true ;;
    firewalld) firewall-cmd --reload >/dev/null 2>&1 || true ;;
    iptables) persist_iptables || true ;;
  esac
}

meta_get() {
  local key="$1" default="${2:-}"
  if [[ -f "$HY_META" ]] && grep -qE "^${key}=" "$HY_META"; then
    grep -E "^${key}=" "$HY_META" | tail -1 | cut -d= -f2-
  else
    echo "$default"
  fi
}

open_firewall_rules() {
  step "步骤 4/4：开放防火墙端口规则"
  local fw
  fw="$(detect_firewall)"
  info "防火墙后端: ${fw}"

  # 常用端口（HTTP/HTTPS/面板/QUIC）
  info "放行常用端口: TCP 80,443,8080 + UDP 443"
  _fw_open tcp 80
  _fw_open tcp 443
  _fw_open tcp 8080
  _fw_open udp 443

  # 若已安装 hy2，再放行实际节点端口
  local hy_port hop_first hop_last
  hy_port="$(meta_get port)"
  hop_first="$(meta_get hop_first)"
  hop_last="$(meta_get hop_last)"
  if [[ -n "$hy_port" ]]; then
    info "放行 Hysteria2 主端口: UDP ${hy_port}"
    _fw_open udp "$hy_port"
  fi
  if [[ -n "$hop_first" && -n "$hop_last" ]]; then
    info "放行端口跳跃: UDP ${hop_first}-${hop_last}"
    _fw_open_range_udp "$hop_first" "$hop_last"
  fi

  _fw_reload

  case "$fw" in
    none)
      warn "未检测到本机防火墙（或未启用），请到云厂商安全组放行 UDP 端口"
      ;;
    *)
      ok "本机防火墙规则已写入 (${fw})"
      ;;
  esac
  warn "提醒: 云服务器还需在控制台安全组放行相同端口"
}

# ========== 3. 执行安装脚本 ==========
run_install_script() {
  step "步骤 3/4：下载并执行 install-hy2.sh"
  local tmp
  tmp="$(mktemp /tmp/install-hy2.XXXXXX.sh)"
  info "下载: ${REPO_RAW_INSTALL}"
  curl -fsSL "$REPO_RAW_INSTALL" -o "$tmp" || die "下载 install-hy2.sh 失败"
  chmod 700 "$tmp"

  # 已是 root，直接跑；参数透传（onekey / interactive / 空=菜单）
  if [[ $# -gt 0 ]]; then
    info "参数: $*"
    bash "$tmp" "$@"
  else
    info "进入安装菜单（交互式 / 一键 / 管理）"
    bash "$tmp"
  fi
  local rc=$?
  rm -f "$tmp"
  if [[ $rc -ne 0 ]]; then
    warn "install-hy2.sh 退出码: $rc（若你是菜单里选了退出，可忽略）"
  else
    ok "install-hy2.sh 执行结束"
  fi
  return 0
}

main() {
  echo "#############################################################"
  echo -e "#     ${GREEN}${BOLD}Hysteria 2 一键启动链 start.sh${PLAIN}                     #"
  echo "#  1.root  2.更新源/包  3.安装脚本  4.开放端口              #"
  echo "#############################################################"

  ensure_root "$@"
  update_packages
  run_install_script "$@"
  open_firewall_rules

  echo
  ok "全部步骤完成"
  echo -e "  管理/重装可再执行: ${YELLOW}curl -fsSL ${REPO_RAW_START} | sudo bash${PLAIN}"
  echo -e "  或: ${YELLOW}bash <(curl -fsSL ${REPO_RAW_INSTALL})${PLAIN}"
}

main "$@"
