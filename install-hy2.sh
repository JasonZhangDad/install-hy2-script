#!/usr/bin/env bash
#
# Hysteria 2 一键安装脚本（必须 root）
# Repo: https://github.com/JasonZhangDad/install-hy2-script
#
# 推荐运行:
#   # 已是 root
#   bash <(curl -fsSL https://raw.githubusercontent.com/JasonZhangDad/install-hy2-script/main/install-hy2.sh)
#   # 非 root（推荐）
#   curl -fsSL https://raw.githubusercontent.com/JasonZhangDad/install-hy2-script/main/install-hy2.sh | sudo bash
#

set -euo pipefail

export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

# 当通过 curl | bash 运行时，stdin 不是终端；把输入切到 /dev/tty 以支持交互
# 无可用 TTY 时静默跳过（避免 CI / 非交互环境报错）
if [[ ! -t 0 ]]; then
  if { exec 3</dev/tty; } 2>/dev/null; then
    exec 0<&3
    exec 3<&-
  fi
fi

### 常量 ###
SCRIPT_VERSION="1.5.3"
SYSCTL_HY2_CONF="/etc/sysctl.d/99-hysteria2.conf"
REPO_RAW="https://raw.githubusercontent.com/JasonZhangDad/install-hy2-script/main/install-hy2.sh"
# raw.githubusercontent.com 有约 5 分钟 CDN 缓存，自更新/提权重下时必须绕开，
# 否则刚推的新版拉不到。用法: curl -fsSL "$(nocache_url)"
nocache_url() { echo "${REPO_RAW}?t=$(date +%s)"; }
OFFICIAL_INSTALLER="https://get.hy2.sh/"
HY_BIN="/usr/local/bin/hysteria"
HY_DIR="/etc/hysteria"
HY_CONF="${HY_DIR}/config.yaml"
HY_META="${HY_DIR}/install.meta"
CLIENT_DIR="/root/hy"
SERVICE_NAME="hysteria-server"
DEFAULT_SNI="www.bing.com"
DEFAULT_MASQUERADE="www.bing.com"

RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
BLUE="\033[34m"
PLAIN="\033[0m"
BOLD="\033[1m"

### 工具函数 ###
red()    { echo -e "${RED}${BOLD}$*${PLAIN}"; }
green()  { echo -e "${GREEN}${BOLD}$*${PLAIN}"; }
yellow() { echo -e "${YELLOW}${BOLD}$*${PLAIN}"; }
blue()   { echo -e "${BLUE}${BOLD}$*${PLAIN}"; }
info()   { echo -e "${GREEN}[INFO]${PLAIN} $*"; }
warn()   { echo -e "${YELLOW}[WARN]${PLAIN} $*"; }
err()    { echo -e "${RED}[ERROR]${PLAIN} $*" >&2; }

### 排版 ###
# 中英文混排时，用 # 拼固定宽度边框必然错位（CJK 占 2 列、ANSI 转义占 0 列），
# 统一改成「分隔线 + 缩进」，任何宽度终端都不会歪。
HR_LINE="────────────────────────────────────────────────────────────"
hr()      { echo -e "${BLUE}${HR_LINE}${PLAIN}"; }
title()   { hr; echo -e "  ${BOLD}${GREEN}$*${PLAIN}"; hr; }
section() { echo; echo -e "${BLUE}──${PLAIN} ${BOLD}$*${PLAIN} ${BLUE}──${PLAIN}"; }
item()    { echo -e "  ${GREEN}$1.${PLAIN} ${*:2}"; }
itemc()   { local c="$1" n="$2"; shift 2; echo -e "  ${c}${n}.${PLAIN} $*"; }
hint()    { echo -e "     ${YELLOW}$*${PLAIN}"; }

die() {
  err "$*"
  exit 1
}

pause() {
  echo
  read -rp "按回车返回菜单..." _
}

# 是否为磁盘上的真实脚本路径（排除 /dev/fd、进程替换等）
_is_real_script_path() {
  local p="${1:-}"
  [[ -n "$p" ]] || return 1
  [[ -f "$p" && -r "$p" ]] || return 1
  case "$p" in
    /dev/fd/*|/proc/self/fd/*|/proc/*/fd/*) return 1 ;;
  esac
  return 0
}

# 必须 root：非 root 时自动 sudo 提权重跑（本地文件 / curl 管道 / 进程替换均可）
need_root() {
  local uid
  uid="${EUID:-$(id -u 2>/dev/null || echo 1)}"
  if [[ "$uid" -eq 0 ]]; then
    return 0
  fi

  if [[ "${HY2_ROOT_REEXEC:-}" == "1" ]]; then
    err "已尝试 sudo 提权，但仍不是 root。请手动执行："
    err "  curl -fsSL \"${REPO_RAW}?t=\$(date +%s)\" | sudo bash"
    exit 1
  fi

  if ! command -v sudo >/dev/null 2>&1; then
    err "本脚本必须使用 root 权限运行，且系统未找到 sudo。"
    err "请切换 root 后执行: bash <(curl -fsSL \"${REPO_RAW}?t=\$(date +%s)\")"
    exit 1
  fi

  warn "当前用户 $(id -un) (uid=${uid}) 不是 root，正在通过 sudo 提权重新执行..."

  local src="${BASH_SOURCE[0]:-}"
  # 1) 本地真实文件：直接 sudo bash 该文件
  if _is_real_script_path "$src"; then
    exec sudo -E env HY2_ROOT_REEXEC=1 bash "$src" "$@"
  fi

  # 2) curl|bash / process substitution：落到临时文件再 sudo
  local tmp
  # 注意：GNU mktemp 只认模板末尾的 X，"XXXXXX.sh" 会报 too few X's in template
  tmp="$(mktemp /tmp/install-hy2.XXXXXXXX)"
  # shellcheck disable=SC2064
  trap "rm -f '$tmp'" EXIT

  if command -v curl >/dev/null 2>&1 && curl -fsSL "$(nocache_url)" -o "$tmp" 2>/dev/null; then
    chmod 700 "$tmp"
    trap - EXIT
    exec sudo -E env HY2_ROOT_REEXEC=1 bash "$tmp" "$@"
  fi

  # 3) 进程替换仍可读时，拷贝当前脚本内容
  if [[ -n "$src" && -r "$src" ]] && cat "$src" >"$tmp" 2>/dev/null; then
    chmod 700 "$tmp"
    trap - EXIT
    exec sudo -E env HY2_ROOT_REEXEC=1 bash "$tmp" "$@"
  fi

  rm -f "$tmp" 2>/dev/null || true
  trap - EXIT
  err "无法自动提权。请用 root 运行，任选其一："
  err "  sudo -i"
  err "  bash <(curl -fsSL \"${REPO_RAW}?t=\$(date +%s)\")"
  err "  curl -fsSL \"${REPO_RAW}?t=\$(date +%s)\" | sudo bash"
  exit 1
}

rand_pwd() {
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -hex 8
  else
    date +%s%N | md5sum 2>/dev/null | cut -c1-16 || tr -dc 'a-zA-Z0-9' </dev/urandom | head -c 16
  fi
}

rand_port() {
  shuf -i 10000-65000 -n 1 2>/dev/null || echo $((RANDOM % 55000 + 10000))
}

is_port_in_use_udp() {
  local p="$1"
  # $4 才是 Local Address:Port；$5 是 Peer Address，永远是 *:*，
  # 用 $5 会让端口占用检测永远返回"未占用"。
  # 排除 hysteria 自身：改端口时旧端口正被本服务监听，那不是冲突；
  # 不排除的话想沿用原端口会被误判成占用，回车后被迫改成随机端口。
  ss -H -ulnp 2>/dev/null | grep -vi hysteria | awk '{print $4}' | sed 's/.*://g' | grep -qx "$p"
}

pick_free_udp_port() {
  local want="${1:-}"
  local port="$want"
  [[ -z "$port" ]] && port="$(rand_port)"

  local tries=0
  while is_port_in_use_udp "$port"; do
    tries=$((tries + 1))
    [[ $tries -gt 50 ]] && die "无法找到可用的 UDP 端口"

    # 没指定端口：随机到占用的就再换一个，不必打扰用户
    if [[ -z "$want" ]]; then
      port="$(rand_port)"
      continue
    fi

    # 指定过端口就由用户决定，不擅自换成随机端口
    err "UDP 端口 ${port} 已被占用"
    if [[ -n "${PORT:-}" ]]; then
      read -rp "换一个端口（回车放弃修改，保持 ${PORT}）: " port
      [[ -z "$port" ]] && { echo "$PORT"; return 0; }
    else
      read -rp "换一个端口（回车随机）: " port
      [[ -z "$port" ]] && { port="$(rand_port)"; continue; }
    fi
    validate_port "$port" || { err "端口不合法: ${port}"; port="$want"; }
  done
  echo "$port"
}

validate_port() {
  local p="$1"
  [[ "$p" =~ ^[0-9]+$ ]] && ((p >= 1 && p <= 65535))
}

# 简单校验域名
validate_domain() {
  local d="$1"
  [[ "$d" =~ ^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?$ ]]
}

### 系统检测与包管理 ###
detect_os() {
  local sys=""
  if [[ -f /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    sys="${ID:-}${ID_LIKE:-}"
    PRETTY_OS="${PRETTY_NAME:-$ID}"
  else
    sys="$(uname -s)"
    PRETTY_OS="$sys"
  fi
  sys="$(echo "$sys" | tr '[:upper:]' '[:lower:]')"

  if echo "$sys" | grep -Eq 'debian|ubuntu'; then
    OS_FAMILY="debian"
    PKG_UPDATE="apt-get update -y"
    PKG_INSTALL="apt-get install -y"
    PKG_REMOVE="apt-get remove -y"
  elif echo "$sys" | grep -Eq 'centos|rhel|rocky|alma|oracle|fedora|amazon|opencloud|anolis|euler'; then
    OS_FAMILY="rhel"
    if command -v dnf >/dev/null 2>&1; then
      PKG_UPDATE="dnf -y makecache"
      PKG_INSTALL="dnf -y install"
      PKG_REMOVE="dnf -y remove"
    else
      PKG_UPDATE="yum -y makecache"
      PKG_INSTALL="yum -y install"
      PKG_REMOVE="yum -y remove"
    fi
  elif echo "$sys" | grep -Eq 'arch|manjaro'; then
    OS_FAMILY="arch"
    PKG_UPDATE="pacman -Sy --noconfirm"
    PKG_INSTALL="pacman -S --noconfirm --needed"
    PKG_REMOVE="pacman -R --noconfirm"
  else
    die "暂不支持当前系统: ${PRETTY_OS:-unknown}。支持 Debian/Ubuntu/CentOS/RHEL/Rocky/Alma/Fedora/Amazon/Arch。"
  fi
  info "检测到系统: ${PRETTY_OS} (${OS_FAMILY})"
}

pkg_install() {
  # shellcheck disable=SC2086
  $PKG_INSTALL "$@"
}

ensure_deps() {
  local deps=(curl wget openssl ca-certificates)
  local missing=()
  local d
  for d in "${deps[@]}"; do
    if ! command -v "$d" >/dev/null 2>&1; then
      # ca-certificates 没有同名命令
      if [[ "$d" == "ca-certificates" ]]; then
        missing+=("$d")
      else
        missing+=("$d")
      fi
    fi
  done

  # 始终尝试补齐常用工具
  local extra=(qrencode socat cron)
  if [[ "$OS_FAMILY" == "rhel" ]]; then
    extra=(qrencode socat cronie)
  elif [[ "$OS_FAMILY" == "arch" ]]; then
    extra=(qrencode socat cronie)
  fi

  info "安装依赖..."
  if [[ "$OS_FAMILY" == "debian" ]]; then
    export DEBIAN_FRONTEND=noninteractive
    # shellcheck disable=SC2086
    $PKG_UPDATE >/dev/null 2>&1 || true
  fi

  # qrencode / iptables-persistent 可能不在默认源，失败不致命
  pkg_install curl wget openssl ca-certificates 2>/dev/null || pkg_install curl wget openssl || true

  if [[ "$OS_FAMILY" == "debian" ]]; then
    pkg_install qrencode socat cron iptables iptables-persistent netfilter-persistent 2>/dev/null || \
      pkg_install qrencode socat cron iptables 2>/dev/null || true
  elif [[ "$OS_FAMILY" == "rhel" ]]; then
    pkg_install qrencode socat cronie iptables iptables-services 2>/dev/null || \
      pkg_install socat cronie iptables 2>/dev/null || true
  else
    pkg_install qrencode socat cronie iptables 2>/dev/null || true
  fi

  command -v curl >/dev/null 2>&1 || die "curl 安装失败"
  command -v openssl >/dev/null 2>&1 || die "openssl 安装失败"
}

### 网络 / IP ###
get_public_ip() {
  local ip=""
  ip="$(curl -fsS4 --max-time 8 https://api.ipify.org 2>/dev/null || true)"
  if [[ -z "$ip" ]]; then
    ip="$(curl -fsS4 --max-time 8 https://ifconfig.me 2>/dev/null || true)"
  fi
  if [[ -z "$ip" ]]; then
    ip="$(curl -fsS6 --max-time 8 https://api64.ipify.org 2>/dev/null || true)"
  fi
  if [[ -z "$ip" ]]; then
    ip="$(curl -fsS4 --max-time 8 https://ip.sb 2>/dev/null || true)"
  fi
  echo "$ip"
}

format_host() {
  local ip="$1"
  if [[ "$ip" == *:* ]]; then
    echo "[$ip]"
  else
    echo "$ip"
  fi
}

### meta 读写（避免 sed 行号踩坑）###
meta_set() {
  local key="$1" value="$2" tmp
  mkdir -p "$HY_DIR"
  touch "$HY_META"
  chmod 600 "$HY_META" 2>/dev/null || true
  # 不用 sed：value 是密码等任意内容，含 | 会破坏替换表达式并留下带密码的 .bak
  # 改为「过滤旧行 + 追加新行 + 原子替换」，对任何字符都安全
  tmp="$(mktemp "${HY_DIR}/.meta.XXXXXX")"
  chmod 600 "$tmp"
  grep -vE "^${key}=" "$HY_META" >"$tmp" 2>/dev/null || true
  printf '%s=%s\n' "$key" "$value" >>"$tmp"
  mv -f "$tmp" "$HY_META"
  chmod 600 "$HY_META" 2>/dev/null || true
}

meta_get() {
  local key="$1" default="${2:-}"
  if [[ -f "$HY_META" ]] && grep -qE "^${key}=" "$HY_META"; then
    grep -E "^${key}=" "$HY_META" | tail -1 | cut -d= -f2-
  else
    echo "$default"
  fi
}

### 证书 / 权限（官方服务以 User=hysteria 运行，必须可读配置）###
get_hy_user() {
  # 优先系统用户 hysteria（官方安装器默认）
  if id hysteria >/dev/null 2>&1; then
    echo "hysteria"
    return 0
  fi
  local u=""
  if [[ -f /etc/systemd/system/hysteria-server.service ]]; then
    u="$(grep -E '^User=' /etc/systemd/system/hysteria-server.service 2>/dev/null | tail -1 | cut -d= -f2 | tr -d '[:space:]' || true)"
  fi
  if [[ -n "$u" ]] && id "$u" >/dev/null 2>&1; then
    echo "$u"
    return 0
  fi
  echo "root"
}

# 以指定用户测试文件可读。0=可读 1=不可读 2=无可用工具（无法验证）
# 很多纯 root 的精简系统没装 sudo，不能只靠 sudo 判断，否则会误判成权限失败
can_user_read() {
  local u="$1" f="$2"
  if command -v runuser >/dev/null 2>&1; then
    runuser -u "$u" -- test -r "$f" 2>/dev/null
  elif command -v sudo >/dev/null 2>&1; then
    sudo -u "$u" test -r "$f" 2>/dev/null
  elif command -v su >/dev/null 2>&1; then
    su -s /bin/sh -c "test -r '$f'" "$u" 2>/dev/null
  else
    return 2
  fi
}

# 把证书挪到 /etc/hysteria，避免 /root 700 导致 hysteria 读不到
relocate_certs_if_needed() {
  local changed=0
  if [[ -n "${CERT_PATH:-}" && -f "${CERT_PATH}" ]]; then
    case "$CERT_PATH" in
      "${HY_DIR}"/*) ;;
      *)
        mkdir -p "$HY_DIR"
        cp -f "$CERT_PATH" "${HY_DIR}/cert.crt"
        CERT_PATH="${HY_DIR}/cert.crt"
        changed=1
        ;;
    esac
  fi
  if [[ -n "${KEY_PATH:-}" && -f "${KEY_PATH}" ]]; then
    case "$KEY_PATH" in
      "${HY_DIR}"/*) ;;
      *)
        mkdir -p "$HY_DIR"
        cp -f "$KEY_PATH" "${HY_DIR}/private.key"
        KEY_PATH="${HY_DIR}/private.key"
        changed=1
        ;;
    esac
  fi
  # 若 config 已存在且仍写着 /root 路径，改成 /etc/hysteria
  if [[ -f "$HY_CONF" ]] && grep -qE '/root/|/home/' "$HY_CONF" 2>/dev/null; then
    sed -i.bak \
      -e "s|^  cert:.*|  cert: ${HY_DIR}/cert.crt|" \
      -e "s|^  key:.*|  key: ${HY_DIR}/private.key|" \
      "$HY_CONF" 2>/dev/null || true
    rm -f "${HY_CONF}.bak"
    CERT_PATH="${HY_DIR}/cert.crt"
    KEY_PATH="${HY_DIR}/private.key"
    changed=1
  fi
  return 0
}

# 强制修正 /etc/hysteria 权限（不做 || true 静默失败）
fix_hy_permissions() {
  local user
  user="$(get_hy_user)"
  mkdir -p "$HY_DIR"
  chmod 755 "$HY_DIR" || true

  relocate_certs_if_needed

  # 清掉历史 sed -i.bak 残留：那是一份旧 config 副本，含旧密码且通常是 644
  rm -f "${HY_DIR}"/*.bak 2>/dev/null || true

  # config / meta 含明文密码，只给属主读（chown 到运行用户后 600 依然读得到）；
  # 证书公钥本就是公开信息，644 无妨；私钥 600。
  if [[ -f "${HY_DIR}/cert.crt" ]]; then
    chmod 644 "${HY_DIR}/cert.crt" || true
  fi
  if [[ -f "${HY_DIR}/private.key" ]]; then
    chmod 600 "${HY_DIR}/private.key" || true
  fi
  if [[ -n "${CERT_PATH:-}" && -f "$CERT_PATH" ]]; then
    chmod 644 "$CERT_PATH" || true
  fi
  if [[ -n "${KEY_PATH:-}" && -f "$KEY_PATH" ]]; then
    chmod 600 "$KEY_PATH" || true
  fi

  if [[ "$user" != "root" ]]; then
    if ! id "$user" >/dev/null 2>&1; then
      warn "用户 ${user} 不存在，尝试创建..."
      useradd -r -d /var/lib/hysteria -m "$user" 2>/dev/null || true
    fi
    if id "$user" >/dev/null 2>&1; then
      chown -R "${user}:${user}" "$HY_DIR" || err "chown ${HY_DIR} 失败"
    else
      warn "无 hysteria 用户，config 保持 root 属主"
    fi
  fi

  # chown 之后再收权限，确保属主已经是运行用户
  [[ -f "$HY_CONF" ]] && { chmod 600 "$HY_CONF" || true; }
  [[ -f "$HY_META" ]] && { chmod 600 "$HY_META" || true; }

  info "权限已设置（运行用户: ${user}） ls:"
  ls -la "$HY_DIR" 2>/dev/null || true
}

# 启动前必须通过：hysteria 用户能读 config
ensure_config_readable() {
  fix_hy_permissions
  local user
  user="$(get_hy_user)"
  [[ -f "$HY_CONF" ]] || die "配置不存在: $HY_CONF"

  if [[ "$user" == "root" ]]; then
    return 0
  fi

  local rc=0
  can_user_read "$user" "$HY_CONF" || rc=$?
  if [[ $rc -eq 0 ]]; then
    green "[OK] config 对 ${user} 可读"
    return 0
  fi
  if [[ $rc -eq 2 ]]; then
    warn "系统无 sudo/runuser/su，跳过可读性验证（权限已按 ${user} 设置）"
    return 0
  fi

  # 二次强制修复。注意不碰 /etc 自身权限——那是整机安全基线，
  # 修 hysteria 的配置没有任何理由放宽它
  warn "配置对 ${user} 仍不可读，强制修复..."
  chmod 755 "$HY_DIR"
  chown -R "${user}:${user}" "$HY_DIR"
  chown "${user}:${user}" "$HY_CONF"
  chmod 600 "$HY_CONF"

  rc=0
  can_user_read "$user" "$HY_CONF" || rc=$?
  if [[ $rc -eq 0 ]]; then
    green "[OK] 强制修复后 config 可读"
    return 0
  fi

  # 还不行就按 600 -> 640 降一级（属组给运行用户）。
  # 不降到 644：config 含明文密码，全局可读等于泄露
  warn "600 仍不可读，降级为 640 (root:${user})"
  chown "root:${user}" "$HY_CONF" 2>/dev/null || true
  chmod 640 "$HY_CONF" 2>/dev/null || true
  rc=0
  can_user_read "$user" "$HY_CONF" || rc=$?
  if [[ $rc -eq 0 ]]; then
    green "[OK] 降级 640 后 config 可读"
    return 0
  fi

  err "无法让用户 ${user} 读取 ${HY_CONF}"
  ls -la "$HY_DIR" || true
  namei -l "$HY_CONF" 2>/dev/null || true
  die "权限修复失败，请检查目录 ACL/挂载选项"
}

# 一键修复已损坏安装的权限并启动
repair_and_start() {
  echo
  green "修复 Hysteria 配置/证书权限并重启服务"
  if [[ ! -f "$HY_CONF" ]]; then
    err "未找到 $HY_CONF，请先安装"
    return 1
  fi
  # 从已有 config 解析 cert/key 路径
  CERT_PATH="$(grep -E '^\s*cert:' "$HY_CONF" 2>/dev/null | awk '{print $2}' | tr -d '\"' | head -1 || true)"
  KEY_PATH="$(grep -E '^\s*key:' "$HY_CONF" 2>/dev/null | awk '{print $2}' | tr -d '\"' | head -1 || true)"
  ensure_config_readable
  systemctl daemon-reload
  systemctl restart "${SERVICE_NAME}.service"
  sleep 1
  if systemctl is-active --quiet "${SERVICE_NAME}.service"; then
    green "修复成功，服务已运行"
    systemctl status "${SERVICE_NAME}.service" --no-pager -l | head -20 || true
  else
    err "修复后仍失败，日志:"
    journalctl -u "${SERVICE_NAME}.service" -n 30 --no-pager || true
    return 1
  fi
}

gen_self_signed() {
  local sni="${1:-$DEFAULT_SNI}"
  mkdir -p "$HY_DIR"
  local cert="${HY_DIR}/cert.crt"
  local key="${HY_DIR}/private.key"

  openssl ecparam -genkey -name prime256v1 -out "$key" 2>/dev/null
  openssl req -new -x509 -days 36500 -key "$key" -out "$cert" \
    -subj "/CN=${sni}" 2>/dev/null

  CERT_PATH="$cert"
  KEY_PATH="$key"
  HY_DOMAIN="$sni"
  CERT_MODE="self"
  CLIENT_INSECURE="true"
  fix_hy_permissions
  green "已生成自签证书，SNI/CN: $sni"
}

install_acme_cert() {
  local domain="$1"
  [[ -n "$domain" ]] || die "域名不能为空"
  validate_domain "$domain" || die "域名格式不合法: $domain"

  local ip
  ip="$(get_public_ip)"
  [[ -n "$ip" ]] || die "无法获取本机公网 IP，请检查网络"

  info "本机公网 IP: $ip"
  info "检查域名 ${domain} 解析..."
  local resolved
  resolved="$(curl -fsS --max-time 10 "https://1.1.1.1/dns-query?name=${domain}&type=A" \
    -H 'accept: application/dns-json' 2>/dev/null | grep -oE '"data":"[0-9.]+"' | head -1 | cut -d\" -f4 || true)"
  if [[ -z "$resolved" ]]; then
    resolved="$(getent ahostsv4 "$domain" 2>/dev/null | awk '{print $1}' | head -1 || true)"
  fi
  if [[ -z "$resolved" ]]; then
    resolved="$(dig +short A "$domain" 2>/dev/null | head -1 || true)"
  fi

  if [[ -n "$resolved" && "$resolved" != "$ip" ]]; then
    warn "域名解析 IP ($resolved) 与本机公网 IP ($ip) 不一致"
    yellow "若使用了 CDN（如 Cloudflare 小黄云），请先关闭代理仅保留 DNS"
    read -rp "仍要继续申请证书？[y/N]: " cont
    [[ "${cont,,}" == "y" || "${cont,,}" == "yes" ]] || die "已取消 ACME 申请"
  fi

  # 安装 acme.sh
  if [[ ! -f /root/.acme.sh/acme.sh ]]; then
    info "安装 acme.sh ..."
    curl -fsSL https://get.acme.sh | sh -s email="hy2-$(date +%s)@example.com" || die "acme.sh 安装失败"
  fi
  # shellcheck disable=SC1091
  source /root/.acme.sh/acme.sh.env 2>/dev/null || true

  local acme="/root/.acme.sh/acme.sh"
  [[ -x "$acme" ]] || acme="bash /root/.acme.sh/acme.sh"

  $acme --set-default-ca --server letsencrypt >/dev/null 2>&1 || true

  # standalone 需要 80 端口
  if ss -H -tlnp 2>/dev/null | awk '{print $4}' | grep -Eq '(:|\\.)80$'; then
    warn "检测到 80 端口被占用，ACME HTTP-01 可能失败"
    read -rp "是否继续？[y/N]: " cont
    [[ "${cont,,}" == "y" || "${cont,,}" == "yes" ]] || die "已取消"
  fi

  # ACME HTTP-01 需要 80/tcp：按当前防火墙自动放行
  info "为 ACME 申请证书，自动放行 TCP 80..."
  open_firewall_tcp 80

  info "申请证书: $domain"
  local issue_args=(-d "$domain" --standalone -k ec-256 --force)
  if [[ "$ip" == *:* ]]; then
    issue_args+=(--listen-v6)
  fi
  if ! $acme --issue "${issue_args[@]}"; then
    die "证书申请失败。请确认: 1) 域名已解析到本机 2) 80 端口可达 3) 防火墙已放行 80/tcp"
  fi

  # 必须装到 /etc/hysteria，供 hysteria 用户读取（不能放 /root）
  local cert="${HY_DIR}/cert.crt"
  local key="${HY_DIR}/private.key"
  mkdir -p "$HY_DIR"

  # acme.sh 以 root 续期，会把这两个文件重写成 root:root 600。
  # 服务以 hysteria 用户跑，只 restart 的话续期后必然启动失败（约 60 天后爆炸），
  # 所以 reloadcmd 里必须先补回属主和权限。用户名在申请时就固定下来，
  # 因为续期时脚本本身可能已经不在磁盘上了。
  local hy_user
  hy_user="$(get_hy_user)"
  local reload_cmd="chown ${hy_user}:${hy_user} '${cert}' '${key}' 2>/dev/null || true; chmod 644 '${cert}' 2>/dev/null || true; chmod 600 '${key}' 2>/dev/null || true; systemctl restart ${SERVICE_NAME}.service 2>/dev/null || true"

  $acme --install-cert -d "$domain" --ecc \
    --fullchain-file "$cert" \
    --key-file "$key" \
    --reloadcmd "$reload_cmd" \
    || die "证书安装失败"

  CERT_PATH="$cert"
  KEY_PATH="$key"
  HY_DOMAIN="$domain"
  CERT_MODE="acme"
  CLIENT_INSECURE="false"
  fix_hy_permissions
  green "ACME 证书申请成功: $domain（已安装到 ${HY_DIR}）"
}

choose_cert() {
  section "证书申请方式"
  item 1 "自签证书 ${YELLOW}（默认，SNI=${DEFAULT_SNI}）${PLAIN}"
  item 2 "ACME 自动申请（需域名解析到本机）"
  item 3 "自定义证书路径"
  echo
  read -rp "请输入选项 [1-3]（回车默认 1）: " cert_input
  cert_input="${cert_input:-1}"

  case "$cert_input" in
    2)
      read -rp "请输入域名: " domain
      [[ -n "$domain" ]] || die "未输入域名"
      install_acme_cert "$domain"
      ;;
    3)
      read -rp "请输入证书（fullchain/crt）路径: " cert_path
      read -rp "请输入私钥（key）路径: " key_path
      read -rp "请输入证书对应域名/SNI: " domain
      [[ -f "$cert_path" && -s "$cert_path" ]] || die "证书文件不存在或为空: $cert_path"
      [[ -f "$key_path" && -s "$key_path" ]] || die "私钥文件不存在或为空: $key_path"
      [[ -n "$domain" ]] || die "域名/SNI 不能为空"
      CERT_PATH="$cert_path"
      KEY_PATH="$key_path"
      HY_DOMAIN="$domain"
      CERT_MODE="custom"
      CLIENT_INSECURE="false"
      read -rp "客户端是否跳过证书校验 insecure？[y/N]（自签或域名不匹配时选 y）: " inc
      if [[ "${inc,,}" == "y" || "${inc,,}" == "yes" ]]; then
        CLIENT_INSECURE="true"
      fi
      green "已使用自定义证书，SNI: $domain"
      ;;
    *)
      read -rp "自签证书 SNI/CN（回车默认 ${DEFAULT_SNI}）: " sni
      sni="${sni:-$DEFAULT_SNI}"
      gen_self_signed "$sni"
      ;;
  esac
}

### 端口 / 端口跳跃 ###
clear_port_hop_rules() {
  local first last mainp
  first="$(meta_get hop_first)"
  last="$(meta_get hop_last)"
  mainp="$(meta_get port)"
  if [[ -n "$first" && -n "$last" && -n "$mainp" ]]; then
    iptables -t nat -D PREROUTING -p udp --dport "${first}:${last}" -j DNAT --to-destination ":${mainp}" 2>/dev/null || true
    ip6tables -t nat -D PREROUTING -p udp --dport "${first}:${last}" -j DNAT --to-destination ":${mainp}" 2>/dev/null || true
  fi
}

apply_port_hop() {
  local first="$1" last="$2" mainp="$3"
  iptables -t nat -A PREROUTING -p udp --dport "${first}:${last}" -j DNAT --to-destination ":${mainp}" 2>/dev/null || \
    warn "iptables 规则添加失败（可能缺少权限或未安装 iptables）"
  ip6tables -t nat -A PREROUTING -p udp --dport "${first}:${last}" -j DNAT --to-destination ":${mainp}" 2>/dev/null || true

  if command -v netfilter-persistent >/dev/null 2>&1; then
    netfilter-persistent save >/dev/null 2>&1 || true
  elif command -v service >/dev/null 2>&1; then
    service iptables save >/dev/null 2>&1 || true
  fi

  meta_set hop_first "$first"
  meta_set hop_last "$last"
}

choose_port() {
  echo
  # 改端口场景下 PORT 已由 load_from_meta 填好。回车是"随机"不是"保持不变"，
  # 不提示的话很容易一回车就把能用的端口换掉
  if [[ -n "${PORT:-}" ]]; then
    yellow "当前端口: ${PORT}"
    yellow "要保持不变请手动输入 ${PORT}；直接回车会随机换一个新端口"
  fi
  read -rp "设置 Hysteria 2 端口 [1-65535]（回车随机）: " port_in
  if [[ -n "$port_in" ]]; then
    validate_port "$port_in" || die "端口不合法: $port_in"
  fi
  PORT="$(pick_free_udp_port "${port_in:-}")"
  yellow "主端口: $PORT"

  section "端口模式"
  item 1 "单端口 ${YELLOW}（默认）${PLAIN}"
  item 2 "端口跳跃（iptables DNAT 一段 UDP 端口到主端口）"
  echo
  read -rp "请输入选项 [1-2]（回车默认 1）: " jump_in
  jump_in="${jump_in:-1}"

  HOP_FIRST=""
  HOP_LAST=""
  LAST_PORT="$PORT"

  if [[ "$jump_in" == "2" ]]; then
    read -rp "起始端口（建议 10000-65535）: " HOP_FIRST
    read -rp "结束端口（必须大于起始端口）: " HOP_LAST
    validate_port "$HOP_FIRST" || die "起始端口不合法"
    validate_port "$HOP_LAST" || die "结束端口不合法"
    ((HOP_FIRST < HOP_LAST)) || die "起始端口必须小于结束端口"
    apply_port_hop "$HOP_FIRST" "$HOP_LAST" "$PORT"
    LAST_PORT="${PORT},${HOP_FIRST}-${HOP_LAST}"
    green "已启用端口跳跃: ${HOP_FIRST}-${HOP_LAST} -> ${PORT}"
  else
    meta_set hop_first ""
    meta_set hop_last ""
  fi
}

# 密码会同时进 YAML 配置和分享链接 URL，限制为 URL unreserved 字符集，
# 否则 ": " 会让 YAML 解析失败、"*" 会被当成 alias、"|" 会破坏 meta 写入
validate_password() {
  local p="$1"
  [[ "$p" =~ ^[A-Za-z0-9._~-]{1,128}$ ]]
}

choose_password() {
  echo
  while true; do
    read -rp "设置连接密码（回车随机，限字母数字与 . _ ~ -）: " AUTH_PWD
    AUTH_PWD="${AUTH_PWD:-$(rand_pwd)}"
    validate_password "$AUTH_PWD" && break
    err "密码含不支持的字符（会破坏 YAML 配置与分享链接），请只用字母、数字和 . _ ~ -"
  done
  yellow "密码: $AUTH_PWD"
}

choose_masquerade() {
  echo
  while true; do
    read -rp "伪装网站（去掉 https://，回车默认 ${DEFAULT_MASQUERADE}）: " PROXY_SITE
    PROXY_SITE="${PROXY_SITE:-$DEFAULT_MASQUERADE}"
    # 去掉协议和路径
    PROXY_SITE="${PROXY_SITE#https://}"
    PROXY_SITE="${PROXY_SITE#http://}"
    PROXY_SITE="${PROXY_SITE%%/*}"
    # 未校验的值直接拼进 YAML 的 url 字段，含空格/冒号会写坏配置
    validate_domain "$PROXY_SITE" && break
    err "伪装站域名格式不合法: ${PROXY_SITE}"
  done
  yellow "伪装站: $PROXY_SITE"
}

### 带宽 / 拥塞控制 ###
# 不设 bandwidth -> hysteria2 用 BBR（自适应，丢包时退让）
# 设了 bandwidth -> 切 Brutal（固定速率，无视丢包），跨境高丢包线路上明显更稳
validate_mbps() {
  local v="$1"
  [[ "$v" =~ ^[0-9]+$ ]] && ((v >= 1 && v <= 10000))
}

choose_bandwidth() {
  section "带宽 / 拥塞控制"
  echo -e "  ${GREEN}留空${PLAIN}  BBR    自适应，丢包时退让 ${YELLOW}（默认，适合优质线路）${PLAIN}"
  echo -e "  ${GREEN}填写${PLAIN}  Brutal 固定速率，无视丢包 ${YELLOW}（适合跨境高丢包线路）${PLAIN}"
  echo
  yellow "填你本地宽带的真实速率，并往下调 10~20%（填太高会自伤式丢包，比不填更差）"
  echo

  read -rp "下行带宽 Mbps（回车 = 不启用 / 关闭 Brutal，回到 BBR）: " BW_DOWN
  if [[ -z "$BW_DOWN" ]]; then
    BW_UP=""
    yellow "拥塞控制: BBR（未设置带宽）"
    return 0
  fi
  validate_mbps "$BW_DOWN" || die "下行带宽不合法（1-10000 的整数）: $BW_DOWN"

  read -rp "上行带宽 Mbps: " BW_UP
  [[ -n "$BW_UP" ]] || die "已填下行带宽，上行也必须填"
  validate_mbps "$BW_UP" || die "上行带宽不合法（1-10000 的整数）: $BW_UP"

  green "拥塞控制: Brutal（上行 ${BW_UP} Mbps / 下行 ${BW_DOWN} Mbps）"
}

### 写配置 ###
write_server_config() {
  mkdir -p "$HY_DIR"
  relocate_certs_if_needed
  # 统一写进 /etc/hysteria，避免路径跑到 /root
  CERT_PATH="${CERT_PATH:-${HY_DIR}/cert.crt}"
  KEY_PATH="${KEY_PATH:-${HY_DIR}/private.key}"
  case "$CERT_PATH" in
    "${HY_DIR}"/*) ;;
    *) CERT_PATH="${HY_DIR}/cert.crt" ;;
  esac
  case "$KEY_PATH" in
    "${HY_DIR}"/*) ;;
    *) KEY_PATH="${HY_DIR}/private.key" ;;
  esac

  cat >"$HY_CONF" <<EOF
# Hysteria 2 server config
# generated by install-hy2-script v${SCRIPT_VERSION}

listen: :${PORT}

tls:
  cert: ${CERT_PATH}
  key: ${KEY_PATH}

auth:
  type: password
  password: ${AUTH_PWD}

quic:
  initStreamReceiveWindow: 16777216
  maxStreamReceiveWindow: 16777216
  initConnReceiveWindow: 33554432
  maxConnReceiveWindow: 33554432

masquerade:
  type: proxy
  proxy:
    url: https://${PROXY_SITE}
    rewriteHost: true
EOF

  # 设了带宽才写 bandwidth（写了就是 Brutal，不写是 BBR）
  # 服务器上传对应客户端下行，所以这里 up/down 与客户端相反
  if [[ -n "${BW_DOWN:-}" && -n "${BW_UP:-}" ]]; then
    cat >>"$HY_CONF" <<EOF

bandwidth:
  up: ${BW_DOWN} mbps
  down: ${BW_UP} mbps
EOF
  fi

  # 关键：chown 给 hysteria，禁止 root-only 600
  ensure_config_readable
}

write_client_files() {
  local ip host insecure_yaml insecure_json insecure_url
  ip="$(get_public_ip)"
  if [[ -z "$ip" ]]; then
    warn "无法自动获取公网 IP，客户端配置中的 server 将使用占位符"
    ip="YOUR_SERVER_IP"
  fi
  host="$(format_host "$ip")"

  if [[ "${CLIENT_INSECURE}" == "true" ]]; then
    insecure_yaml="true"
    insecure_json="true"
    insecure_url="1"
  else
    insecure_yaml="false"
    insecure_json="false"
    insecure_url="0"
  fi

  mkdir -p "$CLIENT_DIR"
  # 目录内每个文件都含密码；/root 通常已是 700，这里再收一道
  chmod 700 "$CLIENT_DIR" 2>/dev/null || true

  # 带宽片段：设了才写，写了就是 Brutal，不写是 BBR
  local bw_yaml="" bw_json="" bw_url="" bw_clash="" bw_sing=""
  if [[ -n "${BW_UP:-}" && -n "${BW_DOWN:-}" ]]; then
    bw_yaml="
bandwidth:
  up: ${BW_UP} mbps
  down: ${BW_DOWN} mbps
"
    bw_json="
  \"bandwidth\": {
    \"up\": \"${BW_UP} mbps\",
    \"down\": \"${BW_DOWN} mbps\"
  },"
    # 多数客户端（NekoBox/Shadowrocket 等）沿用 hysteria1 的这两个参数名
    bw_url="&upmbps=${BW_UP}&downmbps=${BW_DOWN}"
    bw_clash="
    up: \"${BW_UP} Mbps\"
    down: \"${BW_DOWN} Mbps\""
    bw_sing="
  \"up_mbps\": ${BW_UP},
  \"down_mbps\": ${BW_DOWN},"
  fi

  cat >"${CLIENT_DIR}/hy-client.yaml" <<EOF
server: ${host}:${LAST_PORT}

auth: ${AUTH_PWD}

tls:
  sni: ${HY_DOMAIN}
  insecure: ${insecure_yaml}
${bw_yaml}
quic:
  initStreamReceiveWindow: 16777216
  maxStreamReceiveWindow: 16777216
  initConnReceiveWindow: 33554432
  maxConnReceiveWindow: 33554432

fastOpen: true

socks5:
  listen: 127.0.0.1:5678

http:
  listen: 127.0.0.1:5679

transport:
  udp:
    hopInterval: 30s
EOF

  cat >"${CLIENT_DIR}/hy-client.json" <<EOF
{
  "server": "${host}:${LAST_PORT}",
  "auth": "${AUTH_PWD}",
  "tls": {
    "sni": "${HY_DOMAIN}",
    "insecure": ${insecure_json}
  },
  "quic": {
    "initStreamReceiveWindow": 16777216,
    "maxStreamReceiveWindow": 16777216,
    "initConnReceiveWindow": 33554432,
    "maxConnReceiveWindow": 33554432
  },${bw_json}
  "fastOpen": true,
  "socks5": {
    "listen": "127.0.0.1:5678"
  },
  "http": {
    "listen": "127.0.0.1:5679"
  },
  "transport": {
    "udp": {
      "hopInterval": "30s"
    }
  }
}
EOF

  local remark="Hysteria2"
  local url="hysteria2://${AUTH_PWD}@${host}:${PORT}/?insecure=${insecure_url}&sni=${HY_DOMAIN}${bw_url}#${remark}"
  # 端口跳跃时，分享链接主端口仍用主 listen 端口；跳跃范围写在备注
  if [[ -n "${HOP_FIRST:-}" && -n "${HOP_LAST:-}" ]]; then
    url="hysteria2://${AUTH_PWD}@${host}:${PORT}/?insecure=${insecure_url}&sni=${HY_DOMAIN}&mport=${HOP_FIRST}-${HOP_LAST}${bw_url}#${remark}"
  fi
  echo "$url" >"${CLIENT_DIR}/url.txt"

  # Clash Meta / mihomo 片段
  cat >"${CLIENT_DIR}/clash-meta.yaml" <<EOF
proxies:
  - name: "${remark}"
    type: hysteria2
    server: ${ip}
    port: ${PORT}
    password: ${AUTH_PWD}
    sni: ${HY_DOMAIN}
    skip-cert-verify: ${insecure_yaml}${bw_clash}
EOF

  # sing-box outbound 片段
  cat >"${CLIENT_DIR}/sing-box.json" <<EOF
{
  "type": "hysteria2",
  "tag": "${remark}",
  "server": "${ip}",
  "server_port": ${PORT},
  "password": "${AUTH_PWD}",${bw_sing}
  "tls": {
    "enabled": true,
    "server_name": "${HY_DOMAIN}",
    "insecure": ${insecure_json}
  }
}
EOF

  chmod 600 "${CLIENT_DIR}"/hy-client.yaml "${CLIENT_DIR}"/hy-client.json \
            "${CLIENT_DIR}"/clash-meta.yaml "${CLIENT_DIR}"/sing-box.json \
            "${CLIENT_DIR}"/url.txt 2>/dev/null || true

  # 二维码
  if command -v qrencode >/dev/null 2>&1; then
    qrencode -t ANSIUTF8 -o "${CLIENT_DIR}/url-qr.txt" "$url" 2>/dev/null || \
      qrencode -t UTF8 "$url" >"${CLIENT_DIR}/url-qr.txt" 2>/dev/null || true
    qrencode -t PNG -o "${CLIENT_DIR}/url-qr.png" "$url" 2>/dev/null || true
  fi

  # 持久化 meta
  meta_set port "$PORT"
  meta_set last_port "$LAST_PORT"
  meta_set password "$AUTH_PWD"
  meta_set domain "$HY_DOMAIN"
  meta_set cert_path "$CERT_PATH"
  meta_set key_path "$KEY_PATH"
  meta_set cert_mode "$CERT_MODE"
  meta_set insecure "$CLIENT_INSECURE"
  meta_set masquerade "$PROXY_SITE"
  meta_set public_ip "$ip"
  meta_set bw_up "${BW_UP:-}"
  meta_set bw_down "${BW_DOWN:-}"
  if [[ -n "${HOP_FIRST:-}" ]]; then
    meta_set hop_first "$HOP_FIRST"
    meta_set hop_last "$HOP_LAST"
  else
    meta_set hop_first ""
    meta_set hop_last ""
  fi
}

### 服务控制 ###
# install_binary [force|ask]
#   force — 强制装最新版；ask — 已安装时询问；其它 — 已安装则跳过
install_binary() {
  local mode="${1:-ask}"
  info "安装 Hysteria 2 官方二进制..."
  if [[ -x "$HY_BIN" ]]; then
    yellow "已检测到 hysteria: $($HY_BIN version 2>/dev/null | head -1 || echo present)"
    if [[ "$mode" == "force" ]]; then
      bash <(curl -fsSL "$OFFICIAL_INSTALLER") --force || die "官方安装器执行失败"
    elif [[ "$mode" == "ask" ]]; then
      read -rp "是否强制重新安装最新版？[y/N]: " force
      if [[ "${force,,}" == "y" || "${force,,}" == "yes" ]]; then
        bash <(curl -fsSL "$OFFICIAL_INSTALLER") --force || die "官方安装器执行失败"
      fi
    else
      info "已安装，跳过下载（需要更新请用菜单「更新 Hysteria」）"
    fi
  else
    bash <(curl -fsSL "$OFFICIAL_INSTALLER") || die "官方安装器执行失败"
  fi
  [[ -x "$HY_BIN" ]] || die "未找到 $HY_BIN，安装失败"
  green "Hysteria 安装成功: $($HY_BIN version 2>/dev/null | head -1 || echo OK)"
}

# 更新 Hysteria 到最新版（保留现有配置与证书）
update_hysteria() {
  if [[ ! -x "$HY_BIN" ]]; then
    err "未检测到 hysteria 二进制，请先安装"
    return 0
  fi
  local before after
  before="$($HY_BIN version 2>/dev/null | head -1 || echo unknown)"
  yellow "当前版本: $before"
  read -rp "确认更新到官方最新版？[Y/n]: " ans
  ans="${ans:-Y}"
  [[ "${ans,,}" == "y" || "${ans,,}" == "yes" ]] || return 0

  ensure_deps
  bash <(curl -fsSL "$OFFICIAL_INSTALLER") --force || die "更新失败"
  after="$($HY_BIN version 2>/dev/null | head -1 || echo unknown)"
  green "更新完成"
  yellow "之前: $before"
  yellow "现在: $after"

  if [[ -f "$HY_CONF" ]]; then
    read -rp "是否重启 ${SERVICE_NAME} 使新版本生效？[Y/n]: " r
    r="${r:-Y}"
    if [[ "${r,,}" == "y" || "${r,,}" == "yes" ]]; then
      service_restart
    fi
  else
    yellow "未找到服务端配置，跳过重启"
  fi
}

### UDP 缓冲优化（对 Hysteria/QUIC 更直接）###
show_udp_sysctl() {
  section "当前 UDP / 网络缓冲相关参数"
  local keys=(
    net.core.rmem_max
    net.core.wmem_max
    net.core.rmem_default
    net.core.wmem_default
    net.core.netdev_max_backlog
    net.ipv4.udp_rmem_min
    net.ipv4.udp_wmem_min
  )
  local k cur
  for k in "${keys[@]}"; do
    cur="$(sysctl -n "$k" 2>/dev/null || echo N/A)"
    printf "  %-32s %s\n" "$k" "$cur"
  done
  if [[ -f "$SYSCTL_HY2_CONF" ]]; then
    green "已应用脚本优化文件: $SYSCTL_HY2_CONF"
  else
    yellow "尚未通过本脚本写入优化文件"
  fi
}

apply_udp_optimize() {
  info "写入 UDP 缓冲优化: $SYSCTL_HY2_CONF"
  cat >"$SYSCTL_HY2_CONF" <<'EOF'
# Hysteria 2 / QUIC UDP buffer tuning (install-hy2-script)
# 增大套接字缓冲，减少高吞吐时丢包

net.core.rmem_max = 33554432
net.core.wmem_max = 33554432
net.core.rmem_default = 16777216
net.core.wmem_default = 16777216
net.core.netdev_max_backlog = 16384

net.ipv4.udp_rmem_min = 8192
net.ipv4.udp_wmem_min = 8192
EOF

  if sysctl --system >/dev/null 2>&1 || sysctl -p "$SYSCTL_HY2_CONF" >/dev/null 2>&1; then
    green "UDP 缓冲优化已生效"
  else
    # 逐条应用，兼容精简系统
    sysctl -w net.core.rmem_max=33554432 >/dev/null 2>&1 || true
    sysctl -w net.core.wmem_max=33554432 >/dev/null 2>&1 || true
    sysctl -w net.core.rmem_default=16777216 >/dev/null 2>&1 || true
    sysctl -w net.core.wmem_default=16777216 >/dev/null 2>&1 || true
    sysctl -w net.core.netdev_max_backlog=16384 >/dev/null 2>&1 || true
    sysctl -w net.ipv4.udp_rmem_min=8192 >/dev/null 2>&1 || true
    sysctl -w net.ipv4.udp_wmem_min=8192 >/dev/null 2>&1 || true
    green "UDP 缓冲优化已尝试应用（部分参数可能不受当前内核支持）"
  fi
  show_udp_sysctl
}

remove_udp_optimize() {
  if [[ ! -f "$SYSCTL_HY2_CONF" ]]; then
    yellow "未找到 $SYSCTL_HY2_CONF，无需恢复"
    return 0
  fi
  rm -f "$SYSCTL_HY2_CONF"
  sysctl --system >/dev/null 2>&1 || true
  green "已删除脚本优化文件。重启后其余参数以系统默认为准；当前运行中的值可能仍偏大，重启系统可完全恢复。"
}

menu_udp_optimize() {
  section "UDP 缓冲优化（利于 Hysteria 2 / QUIC 高吞吐）"
  item 1 "查看当前参数"
  item 2 "应用优化（写入 ${SYSCTL_HY2_CONF}）"
  item 3 "移除本脚本的优化文件"
  item 0 "返回"
  echo
  read -rp "请选择 [0-3]: " u
  case "$u" in
    1) show_udp_sysctl ;;
    2) apply_udp_optimize ;;
    3) remove_udp_optimize ;;
    *) ;;
  esac
}

service_start() {
  ensure_config_readable
  systemctl daemon-reload
  systemctl enable "${SERVICE_NAME}.service" >/dev/null 2>&1 || true
  systemctl restart "${SERVICE_NAME}.service"
  sleep 1
  if systemctl is-active --quiet "${SERVICE_NAME}.service"; then
    green "服务已启动: ${SERVICE_NAME}"
  else
    err "服务启动失败，最近日志:"
    journalctl -u "${SERVICE_NAME}.service" -n 40 --no-pager || true
    echo
    # 自动再修一次权限并重试
    warn "自动再修权限并重试一次..."
    ensure_config_readable
    systemctl restart "${SERVICE_NAME}.service"
    sleep 1
    if systemctl is-active --quiet "${SERVICE_NAME}.service"; then
      green "重试成功，服务已启动"
      return 0
    fi
    err "尝试前台运行以查看错误:"
    local user
    user="$(get_hy_user)"
    if [[ "$user" != "root" ]] && id "$user" >/dev/null 2>&1; then
      timeout 3s sudo -u "$user" "$HY_BIN" server -c "$HY_CONF" 2>&1 | head -40 || true
    else
      timeout 3s "$HY_BIN" server -c "$HY_CONF" 2>&1 | head -40 || true
    fi
    die "请根据日志排查后重试（管理菜单可选「修复权限并启动」）"
  fi
}

service_restart() {
  ensure_config_readable
  systemctl restart "${SERVICE_NAME}.service"
  sleep 1
  if systemctl is-active --quiet "${SERVICE_NAME}.service"; then
    green "服务已重启"
  else
    err "重启失败"
    journalctl -u "${SERVICE_NAME}.service" -n 30 --no-pager || true
  fi
}

service_stop() {
  systemctl stop "${SERVICE_NAME}.service" 2>/dev/null || true
  systemctl disable "${SERVICE_NAME}.service" 2>/dev/null || true
  yellow "服务已停止"
}

is_installed() {
  [[ -x "$HY_BIN" && -f "$HY_CONF" ]]
}

# 菜单页顶部的一行状态
status_line() {
  if ! is_installed; then
    echo -e "${YELLOW}未安装${PLAIN}"
  elif systemctl is-active --quiet "${SERVICE_NAME}.service" 2>/dev/null; then
    echo -e "${GREEN}已安装 · 运行中${PLAIN}   UDP $(meta_get last_port "$(meta_get port)")"
  else
    echo -e "${RED}已安装 · 未运行${PLAIN}"
  fi
}

### 防火墙：自动识别 ufw / firewalld / iptables ###
# 优先级：正在运行的 ufw > 正在运行的 firewalld > iptables > 无
detect_firewall() {
  if command -v ufw >/dev/null 2>&1; then
    if ufw status 2>/dev/null | grep -qiE 'Status:\s*active'; then
      echo "ufw"
      return 0
    fi
  fi
  if command -v firewall-cmd >/dev/null 2>&1; then
    if systemctl is-active --quiet firewalld 2>/dev/null || firewall-cmd --state 2>/dev/null | grep -qi running; then
      echo "firewalld"
      return 0
    fi
  fi
  if command -v iptables >/dev/null 2>&1; then
    echo "iptables"
    return 0
  fi
  echo "none"
}

persist_iptables() {
  if command -v netfilter-persistent >/dev/null 2>&1; then
    netfilter-persistent save >/dev/null 2>&1 && return 0
  fi
  if command -v service >/dev/null 2>&1; then
    service iptables save >/dev/null 2>&1 && return 0
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

# 仅放行 TCP 端口（ACME 80 等）
open_firewall_tcp() {
  local tport="$1"
  local fw
  fw="$(detect_firewall)"
  case "$fw" in
    ufw)
      ufw allow "${tport}/tcp" comment "hysteria2-tcp" >/dev/null 2>&1 || ufw allow "${tport}/tcp" >/dev/null 2>&1 || true
      ufw reload >/dev/null 2>&1 || true
      green "ufw 已放行 TCP ${tport}"
      ;;
    firewalld)
      firewall-cmd --permanent --add-port="${tport}/tcp" >/dev/null 2>&1 || true
      firewall-cmd --reload >/dev/null 2>&1 || true
      green "firewalld 已放行 TCP ${tport}"
      ;;
    iptables)
      iptables -D INPUT -p tcp --dport "$tport" -j ACCEPT 2>/dev/null || true
      iptables -I INPUT -p tcp --dport "$tport" -j ACCEPT 2>/dev/null || true
      persist_iptables || true
      green "iptables 已放行 TCP ${tport}"
      ;;
    *)
      yellow "未检测到本机防火墙，请手动/在安全组放行 TCP ${tport}"
      ;;
  esac
}

# 放行 UDP 主端口；可选端口跳跃段
# 用法: open_firewall <udp_port> [hop_first] [hop_last]
open_firewall() {
  local p="$1"
  local hop_first="${2:-${HOP_FIRST:-}}"
  local hop_last="${3:-${HOP_LAST:-}}"
  local fw
  fw="$(detect_firewall)"

  echo
  info "防火墙检测结果: ${fw}"

  case "$fw" in
    ufw)
      info "使用 ufw 放行端口..."
      ufw allow "${p}/udp" comment "hysteria2" >/dev/null 2>&1 || ufw allow "${p}/udp" >/dev/null 2>&1 || warn "ufw 放行 UDP ${p} 失败"
      if [[ -n "$hop_first" && -n "$hop_last" ]]; then
        ufw allow "${hop_first}:${hop_last}/udp" comment "hysteria2-hop" >/dev/null 2>&1 || \
          ufw allow "${hop_first}:${hop_last}/udp" >/dev/null 2>&1 || warn "ufw 放行 UDP ${hop_first}-${hop_last} 失败"
      fi
      ufw reload >/dev/null 2>&1 || true
      green "已通过 ufw 放行 UDP ${p}${hop_first:+, 跳跃 ${hop_first}-${hop_last}}"
      ;;
    firewalld)
      info "使用 firewalld 放行端口..."
      firewall-cmd --permanent --add-port="${p}/udp" >/dev/null 2>&1 || warn "firewalld 放行 UDP ${p} 失败"
      if [[ -n "$hop_first" && -n "$hop_last" ]]; then
        firewall-cmd --permanent --add-port="${hop_first}-${hop_last}/udp" >/dev/null 2>&1 || \
          warn "firewalld 放行 UDP ${hop_first}-${hop_last} 失败"
      fi
      firewall-cmd --reload >/dev/null 2>&1 || true
      green "已通过 firewalld 放行 UDP ${p}${hop_first:+, 跳跃 ${hop_first}-${hop_last}}"
      ;;
    iptables)
      info "使用 iptables 放行端口..."
      # 避免重复插入：先删再加（忽略失败）
      iptables -D INPUT -p udp --dport "$p" -j ACCEPT 2>/dev/null || true
      iptables -I INPUT -p udp --dport "$p" -j ACCEPT 2>/dev/null || warn "iptables 放行 UDP ${p} 失败"
      if command -v ip6tables >/dev/null 2>&1; then
        ip6tables -D INPUT -p udp --dport "$p" -j ACCEPT 2>/dev/null || true
        ip6tables -I INPUT -p udp --dport "$p" -j ACCEPT 2>/dev/null || true
      fi
      if [[ -n "$hop_first" && -n "$hop_last" ]]; then
        iptables -D INPUT -p udp --dport "${hop_first}:${hop_last}" -j ACCEPT 2>/dev/null || true
        iptables -I INPUT -p udp --dport "${hop_first}:${hop_last}" -j ACCEPT 2>/dev/null || true
        if command -v ip6tables >/dev/null 2>&1; then
          ip6tables -D INPUT -p udp --dport "${hop_first}:${hop_last}" -j ACCEPT 2>/dev/null || true
          ip6tables -I INPUT -p udp --dport "${hop_first}:${hop_last}" -j ACCEPT 2>/dev/null || true
        fi
      fi
      if persist_iptables; then
        green "已通过 iptables 放行，并尝试持久化规则"
      else
        green "已通过 iptables 放行 UDP ${p}${hop_first:+, 跳跃 ${hop_first}-${hop_last}}"
        yellow "未能自动持久化 iptables，重启后可能失效；可安装 iptables-persistent 或手动 iptables-save"
      fi
      ;;
    *)
      warn "未检测到本机防火墙工具（或 ufw/firewalld 均未启用）"
      yellow "若云厂商有安全组，请在控制台放行: UDP ${p}${hop_first:+ 以及 ${hop_first}-${hop_last}}"
      return 0
      ;;
  esac

  meta_set firewall_backend "$fw"
  yellow "提醒: 云服务器请同时在「安全组 / 防火墙」控制台放行相同 UDP 端口"
}

# 安装后调用：按 meta/全局变量自动放行
hint_firewall() {
  local p="${1:-}"
  if [[ -z "$p" ]]; then
    p="$(meta_get port)"
  fi
  if [[ -z "$p" ]]; then
    warn "无端口信息，跳过防火墙配置"
    return 0
  fi
  local hf hl
  hf="${HOP_FIRST:-$(meta_get hop_first)}"
  hl="${HOP_LAST:-$(meta_get hop_last)}"
  open_firewall "$p" "$hf" "$hl"
}

# 管理菜单：重新检测并放行当前 hy2 端口
reapply_firewall() {
  load_from_meta
  if [[ -z "${PORT:-}" ]]; then
    err "未找到已安装端口，请先安装"
    return 0
  fi
  echo
  green "当前节点端口: UDP ${PORT}"
  if [[ -n "${HOP_FIRST:-}" && -n "${HOP_LAST:-}" ]]; then
    green "端口跳跃: ${HOP_FIRST}-${HOP_LAST}"
  fi
  echo -e "  将自动识别: ${GREEN}ufw${PLAIN} / ${GREEN}firewalld${PLAIN} / ${GREEN}iptables${PLAIN}"
  open_firewall "$PORT" "${HOP_FIRST:-}" "${HOP_LAST:-}"
}

### 连通性自检 ###
# 只读检查，不改任何配置。目的是在给出分享链接前就指出哪一层不通，
# 而不是让用户拿到一个"看起来正常但永远连不上"的链接。
is_private_ip() {
  local ip="$1"
  [[ "$ip" =~ ^10\. ]] && return 0
  [[ "$ip" =~ ^192\.168\. ]] && return 0
  [[ "$ip" =~ ^172\.(1[6-9]|2[0-9]|3[01])\. ]] && return 0
  # 100.64/10 是运营商级 NAT（CGNAT），同样不可入站
  [[ "$ip" =~ ^100\.(6[4-9]|[7-9][0-9]|1[0-1][0-9]|12[0-7])\. ]] && return 0
  return 1
}

# 本机网卡上的全局 IPv4（不含 lo）
nic_ipv4() {
  ip -4 addr show scope global 2>/dev/null | awk '/inet /{print $2}' | cut -d/ -f1 | head -1
}

# 从云厂商元数据服务查"绑定到本机的入站公网 IP"。
# 查不到返回空（不等于没有，可能只是非云环境），能查到空串才说明确实没绑。
cloud_public_ip() {
  local v
  # Azure
  v="$(curl -s -m 2 -H Metadata:true --noproxy '*' \
    "http://169.254.169.254/metadata/instance/network/interface?api-version=2021-02-01" 2>/dev/null \
    | grep -o '"publicIpAddress":"[^"]*"' | head -1 | cut -d'"' -f4 || true)"
  if [[ -n "$v" ]]; then echo "$v"; return 0; fi
  if curl -s -m 2 -H Metadata:true --noproxy '*' \
      "http://169.254.169.254/metadata/instance?api-version=2021-02-01" >/dev/null 2>&1; then
    echo ""; return 0   # 确认是 Azure，且 publicIpAddress 为空
  fi
  # GCP
  v="$(curl -s -m 2 -H 'Metadata-Flavor: Google' --noproxy '*' \
    "http://metadata.google.internal/computeMetadata/v1/instance/network-interfaces/0/access-configs/0/external-ip" 2>/dev/null || true)"
  if [[ -n "$v" ]]; then echo "$v"; return 0; fi
  # 阿里云
  v="$(curl -s -m 2 --noproxy '*' "http://100.100.100.200/latest/meta-data/eipv4" 2>/dev/null || true)"
  if [[ -n "$v" ]]; then echo "$v"; return 0; fi
  # AWS / 腾讯云（IMDSv1 风格）
  v="$(curl -s -m 2 --noproxy '*' "http://169.254.169.254/latest/meta-data/public-ipv4" 2>/dev/null || true)"
  if [[ -n "$v" ]]; then echo "$v"; return 0; fi
  return 1
}

# 本机起客户端连 127.0.0.1，验证服务端配置/证书/密码本身没问题。
# 走环回不经过防火墙和公网，所以能把"服务端问题"和"网络路径问题"分开。
selftest_local() {
  local testport tmpcfg pid rc=1
  [[ -x "$HY_BIN" && -n "${PORT:-}" && -n "${AUTH_PWD:-}" ]] || return 2
  testport=$((20000 + RANDOM % 20000))
  tmpcfg="$(mktemp /tmp/hy2-selftest.XXXXXXXX)"
  chmod 600 "$tmpcfg"
  cat >"$tmpcfg" <<EOF
server: 127.0.0.1:${PORT}
auth: ${AUTH_PWD}
tls:
  sni: ${HY_DOMAIN:-$DEFAULT_SNI}
  insecure: true
socks5:
  listen: 127.0.0.1:${testport}
EOF
  "$HY_BIN" client -c "$tmpcfg" >/dev/null 2>&1 &
  pid=$!
  sleep 3
  if curl -s -m 10 -x "socks5h://127.0.0.1:${testport}" \
      https://www.gstatic.com/generate_204 -o /dev/null 2>/dev/null; then
    rc=0
  fi
  kill "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
  rm -f "$tmpcfg"
  return $rc
}

ck_ok()   { echo -e "  ${GREEN}[OK]${PLAIN}   $*"; }
ck_warn() { echo -e "  ${YELLOW}[WARN]${PLAIN} $*"; }
ck_fail() { echo -e "  ${RED}[FAIL]${PLAIN} $*"; }

diagnose_connectivity() {
  load_from_meta
  section "连通性自检"
  if [[ -z "${PORT:-}" ]]; then
    ck_fail "未找到已安装的端口信息，请先安装"
    return 0
  fi

  # 1. 服务与实际监听端口
  local listen_port=""
  if systemctl is-active --quiet "${SERVICE_NAME}.service" 2>/dev/null; then
    listen_port="$(ss -H -ulnp 2>/dev/null | grep -i hysteria | awk '{print $4}' | sed 's/.*://' | head -1 || true)"
    if [[ -z "$listen_port" ]]; then
      ck_warn "服务在运行，但未从 ss 读到监听端口"
    elif [[ "$listen_port" == "$PORT" ]]; then
      ck_ok "服务监听  UDP ${PORT}"
    else
      ck_fail "服务实际监听 UDP ${listen_port}，与配置的 ${PORT} 不一致 —— 防火墙别开错端口"
    fi
  else
    ck_fail "服务未运行，先修复服务再谈连通性（管理菜单 7）"
  fi

  # 2. 本机防火墙
  local fw
  fw="$(detect_firewall)"
  case "$fw" in
    ufw)
      if ufw status 2>/dev/null | grep -q "${PORT}/udp"; then
        ck_ok "本机防火墙 已放行 UDP ${PORT} (ufw)"
      else
        ck_fail "ufw 未放行 UDP ${PORT}（管理菜单 6 可自动放行）"
      fi ;;
    firewalld)
      if firewall-cmd --list-ports 2>/dev/null | grep -q "${PORT}/udp"; then
        ck_ok "本机防火墙 已放行 UDP ${PORT} (firewalld)"
      else
        ck_fail "firewalld 未放行 UDP ${PORT}（管理菜单 6 可自动放行）"
      fi ;;
    iptables)
      if iptables -S INPUT 2>/dev/null | grep -qE "^-P INPUT ACCEPT" \
         && ! iptables -S INPUT 2>/dev/null | grep -qE '^-A INPUT .*(DROP|REJECT)'; then
        ck_ok "本机防火墙 INPUT 默认放行，无需额外规则 (iptables)"
      elif iptables -S INPUT 2>/dev/null | grep -q "dport ${PORT}"; then
        ck_ok "本机防火墙 已放行 UDP ${PORT} (iptables)"
      else
        ck_fail "iptables 未放行 UDP ${PORT}（管理菜单 6 可自动放行）"
      fi ;;
    *)
      ck_ok "本机未启用防火墙，无需放行" ;;
  esac

  # 3/4. 网卡地址 与 出站地址（判断是否在 NAT 之后）
  local nic out
  nic="$(nic_ipv4)"
  out="$(get_public_ip)"
  local behind_nat=0
  if [[ -n "$nic" ]] && is_private_ip "$nic"; then
    behind_nat=1
    ck_warn "网卡地址 ${nic} 为私网，机器在 NAT 之后"
  elif [[ -n "$nic" ]]; then
    ck_ok "网卡地址 ${nic} 为公网"
  fi
  [[ -n "$out" ]] && ck_ok "出站地址 ${out}"

  # 5. 云元数据：有没有真正可入站的公网 IP —— NAT 场景下这条最关键
  if [[ $behind_nat -eq 1 ]]; then
    local cip rc=0
    cip="$(cloud_public_ip)" || rc=$?
    if [[ $rc -ne 0 ]]; then
      ck_warn "未识别到云元数据服务，无法确认是否有入站公网 IP"
      ck_warn "请自行确认云控制台已为本机绑定公网 IP，并放行 UDP ${PORT}"
    elif [[ -z "$cip" ]]; then
      ck_fail "云元数据显示本机${RED}没有入站公网 IP${PLAIN} —— 外网无法连入！"
      ck_fail "出站的 ${out} 是共享 SNAT 地址，不能用于入站"
      ck_fail "需要：给实例关联公网 IP，或让管理员做 UDP ${PORT} 端口映射"
    else
      ck_ok "云元数据确认入站公网 IP: ${cip}"
      [[ -n "$out" && "$cip" != "$out" ]] && \
        ck_warn "它与出站地址 ${out} 不一致，分享链接请使用 ${cip}"
    fi
  fi

  # 6. 端到端自测（走环回，绕开防火墙与公网）
  local rc=0
  selftest_local || rc=$?
  case $rc in
    0) ck_ok "服务端自测 (socks5 → HTTP 204) 通过，配置/证书/密码均正常" ;;
    2) ck_warn "缺少二进制或配置信息，跳过服务端自测" ;;
    *) ck_fail "服务端自测未通过：本机连自己都失败，问题在服务端而非网络" ;;
  esac

  # 7. 云安全组永远要人工确认
  echo
  yellow "提醒：云服务器还需在【安全组 / 网络ACL】控制台放行 UDP ${PORT}"
  yellow "      本机防火墙与云安全组是独立两层，脚本只能处理前者"
}

### 安装主流程 ###
do_install() {
  if is_installed; then
    warn "检测到已安装 Hysteria 2"
    read -rp "继续将覆盖现有配置，是否继续？[y/N]: " ans
    [[ "${ans,,}" == "y" || "${ans,,}" == "yes" ]] || return 0
    clear_port_hop_rules
  fi

  ensure_deps
  install_binary ask
  choose_cert
  choose_port
  choose_password
  choose_masquerade
  write_server_config
  write_client_files
  service_start
  hint_firewall "$PORT"
  echo
  title "Hysteria 2 安装完成"
  diagnose_connectivity
  show_conf
}

# 一键安装：全默认，不再逐步问证书/端口/密码
# 自签 www.bing.com + 随机端口 + 随机密码 + 伪装 www.bing.com + 单端口
do_quick_install() {
  section "一键安装默认参数"
  echo "  证书   自签 (SNI=${DEFAULT_SNI})"
  echo "  端口   随机 UDP（单端口，无跳跃）"
  echo "  密码   随机生成"
  echo "  伪装   ${DEFAULT_MASQUERADE}"
  echo
  if is_installed; then
    warn "检测到已安装，继续将覆盖现有配置"
    read -rp "确认覆盖并一键重装？[y/N]: " ans
    [[ "${ans,,}" == "y" || "${ans,,}" == "yes" ]] || return 0
    clear_port_hop_rules
  else
    read -rp "确认开始一键安装？[Y/n]: " ans
    ans="${ans:-Y}"
    [[ "${ans,,}" == "y" || "${ans,,}" == "yes" ]] || return 0
  fi

  ensure_deps
  install_binary skip

  gen_self_signed "$DEFAULT_SNI"
  PORT="$(pick_free_udp_port)"
  LAST_PORT="$PORT"
  HOP_FIRST=""
  HOP_LAST=""
  meta_set hop_first ""
  meta_set hop_last ""
  AUTH_PWD="$(rand_pwd)"
  PROXY_SITE="$DEFAULT_MASQUERADE"

  yellow "主端口: $PORT"
  yellow "密码: $AUTH_PWD"

  write_server_config
  write_client_files
  service_start
  hint_firewall "$PORT"

  echo
  title "Hysteria 2 一键安装完成"
  diagnose_connectivity
  show_conf
}

### 卸载 ###
do_uninstall() {
  if ! is_installed && [[ ! -x "$HY_BIN" ]]; then
    warn "未检测到安装"
    return 0
  fi
  read -rp "确认卸载 Hysteria 2？[y/N]: " ans
  [[ "${ans,,}" == "y" || "${ans,,}" == "yes" ]] || return 0

  service_stop
  clear_port_hop_rules

  # 用官方脚本删二进制和 unit（保留我们自己的配置目录手动清理）
  # 固定路径 + root 执行会被本地用户抢跑（软链/预置文件），必须用随机名
  local rm_tmp
  rm_tmp="$(mktemp /tmp/get-hy2.XXXXXXXX)"
  chmod 700 "$rm_tmp"
  if curl -fsSL "$OFFICIAL_INSTALLER" -o "$rm_tmp" 2>/dev/null; then
    bash "$rm_tmp" --remove 2>/dev/null || true
  fi
  rm -f "$rm_tmp"

  rm -rf "$HY_DIR" "$CLIENT_DIR"
  rm -f /root/hy2-cert/cert.crt /root/hy2-cert/private.key 2>/dev/null || true
  # 不自动删除 acme.sh，避免影响其它站点证书

  if command -v netfilter-persistent >/dev/null 2>&1; then
    netfilter-persistent save >/dev/null 2>&1 || true
  fi

  green "Hysteria 2 已卸载"
}

### 服务开关菜单 ###
menu_switch() {
  section "服务管理"
  item 1 "启动"
  item 2 "停止"
  item 3 "重启"
  item 0 "返回"
  echo
  read -rp "请选择 [0-3]: " s
  case "$s" in
    1) service_start ;;
    2) service_stop ;;
    3) service_restart ;;
    *) ;;
  esac
}

### 从 meta / 现有配置加载变量 ###
load_from_meta() {
  PORT="$(meta_get port)"
  LAST_PORT="$(meta_get last_port "$PORT")"
  AUTH_PWD="$(meta_get password)"
  HY_DOMAIN="$(meta_get domain "$DEFAULT_SNI")"
  CERT_PATH="$(meta_get cert_path "${HY_DIR}/cert.crt")"
  KEY_PATH="$(meta_get key_path "${HY_DIR}/private.key")"
  CERT_MODE="$(meta_get cert_mode self)"
  CLIENT_INSECURE="$(meta_get insecure true)"
  PROXY_SITE="$(meta_get masquerade "$DEFAULT_MASQUERADE")"
  HOP_FIRST="$(meta_get hop_first)"
  HOP_LAST="$(meta_get hop_last)"
  BW_UP="$(meta_get bw_up)"
  BW_DOWN="$(meta_get bw_down)"
}

### 修改配置 ###
change_port() {
  is_installed || die "尚未安装"
  load_from_meta
  clear_port_hop_rules
  choose_port
  # 保留其它字段
  write_server_config
  write_client_files
  service_restart
  hint_firewall "$PORT"
  green "端口已更新"
  show_conf
}

change_password() {
  is_installed || die "尚未安装"
  load_from_meta
  choose_password
  write_server_config
  write_client_files
  service_restart
  green "密码已更新"
  show_conf
}

change_cert() {
  is_installed || die "尚未安装"
  load_from_meta
  choose_cert
  write_server_config
  write_client_files
  service_restart
  green "证书已更新"
  show_conf
}

change_masquerade() {
  is_installed || die "尚未安装"
  load_from_meta
  choose_masquerade
  write_server_config
  write_client_files
  service_restart
  green "伪装网站已更新为: $PROXY_SITE"
  show_conf
}

change_bandwidth() {
  is_installed || die "尚未安装"
  load_from_meta
  if [[ -n "${BW_UP:-}" && -n "${BW_DOWN:-}" ]]; then
    yellow "当前: Brutal（上行 ${BW_UP} Mbps / 下行 ${BW_DOWN} Mbps）"
  else
    yellow "当前: BBR（未设置带宽）"
  fi
  choose_bandwidth
  write_server_config
  write_client_files
  service_restart
  green "带宽已更新"
  show_conf
}

menu_change() {
  is_installed || { err "尚未安装"; return 0; }
  section "修改配置"
  item 1 "修改端口 / 端口跳跃"
  item 2 "修改密码"
  item 3 "修改证书"
  item 4 "修改伪装网站"
  item 5 "带宽 / 加速（Brutal ${YELLOW}可选${PLAIN}，默认 BBR）"
  item 0 "返回"
  echo
  read -rp "请选择 [0-5]: " c
  case "$c" in
    1) change_port ;;
    2) change_password ;;
    3) change_cert ;;
    4) change_masquerade ;;
    5) change_bandwidth ;;
    *) ;;
  esac
}

### 显示配置 ###
# 客户端文件缺失时按 meta 重建；0=可用 1=不可用
ensure_client_files() {
  [[ -f "${CLIENT_DIR}/url.txt" ]] && return 0
  if ! is_installed; then
    err "未找到配置，请先安装"
    return 1
  fi
  warn "客户端文件缺失，尝试根据现有配置重新生成..."
  load_from_meta
  if [[ -z "$PORT" || -z "$AUTH_PWD" ]]; then
    err "meta 不完整，请重新安装"
    return 1
  fi
  write_client_files
}

# 只看链接和二维码。SSH 断开后回来最常用的就是这个，
# 不必把整份 YAML/JSON 再刷一屏
show_link() {
  ensure_client_files || return 0
  local url
  url="$(cat "${CLIENT_DIR}/url.txt")"

  section "分享链接"
  red "$url"

  if [[ -f "${CLIENT_DIR}/url-qr.txt" ]]; then
    section "二维码"
    cat "${CLIENT_DIR}/url-qr.txt"
  elif command -v qrencode >/dev/null 2>&1; then
    section "二维码"
    qrencode -t ANSIUTF8 "$url" 2>/dev/null || true
  else
    yellow "未安装 qrencode，无法显示二维码（apt/yum install qrencode）"
  fi

  echo
  yellow "链接文件: ${CLIENT_DIR}/url.txt"
  [[ -f "${CLIENT_DIR}/url-qr.png" ]] && yellow "二维码图片: ${CLIENT_DIR}/url-qr.png"
  if systemctl is-active --quiet "${SERVICE_NAME}.service" 2>/dev/null; then
    green "服务状态: active (running)"
  else
    red "服务状态: inactive / 未运行"
  fi
}

show_conf() {
  ensure_client_files || return 0

  section "服务端配置  ${HY_CONF}"
  if [[ -f "$HY_CONF" ]]; then
    cat "$HY_CONF"
  fi

  section "客户端 YAML  ${CLIENT_DIR}/hy-client.yaml"
  cat "${CLIENT_DIR}/hy-client.yaml"

  section "客户端 JSON  ${CLIENT_DIR}/hy-client.json"
  cat "${CLIENT_DIR}/hy-client.json"

  section "分享链接  ${CLIENT_DIR}/url.txt"
  red "$(cat "${CLIENT_DIR}/url.txt")"

  if [[ -f "${CLIENT_DIR}/url-qr.txt" ]]; then
    section "分享链接二维码"
    cat "${CLIENT_DIR}/url-qr.txt"
  elif command -v qrencode >/dev/null 2>&1; then
    section "分享链接二维码"
    qrencode -t ANSIUTF8 "$(cat "${CLIENT_DIR}/url.txt")" 2>/dev/null || true
  else
    yellow "未安装 qrencode，跳过终端二维码（可 apt/yum install qrencode）"
  fi

  if [[ -f "${CLIENT_DIR}/url-qr.png" ]]; then
    yellow "二维码图片: ${CLIENT_DIR}/url-qr.png"
  fi

  echo
  yellow "客户端文件目录: ${CLIENT_DIR}/"
  yellow "  Clash Meta / mihomo : ${CLIENT_DIR}/clash-meta.yaml"
  yellow "  sing-box outbound   : ${CLIENT_DIR}/sing-box.json"
  if [[ -n "$(meta_get bw_up)" ]]; then
    green "拥塞控制: Brutal（上行 $(meta_get bw_up) / 下行 $(meta_get bw_down) Mbps）"
  else
    yellow "拥塞控制: BBR（未启用 Brutal，可在 管理→修改配置→5 开启）"
  fi
  if systemctl is-active --quiet "${SERVICE_NAME}.service" 2>/dev/null; then
    green "服务状态: active (running)"
  else
    red "服务状态: inactive / 未运行"
  fi
}

update_script() {
  info "从 GitHub 拉取最新脚本..."
  local tmp
  tmp="$(mktemp)"
  if curl -fsSL "$(nocache_url)" -o "$tmp"; then
    local target="/usr/local/bin/install-hy2"
    cp "$tmp" "$target"
    chmod +x "$target"
    rm -f "$tmp"
    green "已更新到 $target"
    yellow "重新运行: install-hy2  或  bash $target"
  else
    rm -f "$tmp"
    err "下载失败"
  fi
}

### 管理子菜单 ###
menu_manage() {
  while true; do
    clear
    title "管理功能"
    echo -e "  状态   $(status_line)"
    echo -e "  防火墙 ${YELLOW}$(detect_firewall)${PLAIN}"
    hr

    section "节点"
    item 1 "查看分享链接 / 二维码"
    item 2 "显示完整配置（YAML / JSON / 链接 / 二维码）"
    item 3 "修改配置（端口 / 密码 / 证书 / 伪装站 / 带宽）"

    section "服务"
    item 4 "启动 / 停止 / 重启"
    item 5 "连通性自检（连不上先跑这个）"
    itemc "$YELLOW" 6 "${YELLOW}修复权限并启动${PLAIN}（permission denied 点这个）"

    section "维护"
    item 7 "自动放行防火墙端口（识别 ufw/firewalld/iptables）"
    item 8 "UDP 缓冲优化"
    item 9 "更新 Hysteria 到最新版"
    item 10 "更新本脚本"

    section "其它"
    itemc "$RED" 11 "卸载 Hysteria 2"
    item 0 "返回上级"
    echo
    read -rp "请输入选项 [0-11]: " m
    case "$m" in
      1) show_link; pause ;;
      2) show_conf; pause ;;
      3) menu_change; pause ;;
      4) menu_switch; pause ;;
      5) diagnose_connectivity; pause ;;
      6) repair_and_start; pause ;;
      7) reapply_firewall; pause ;;
      8) menu_udp_optimize; pause ;;
      9) update_hysteria; pause ;;
      10) update_script; pause ;;
      11) do_uninstall; pause ;;
      0) return 0 ;;
      *) err "无效选项"; sleep 1 ;;
    esac
  done
}

### 主菜单：先选 交互式 / 一键 ###
menu() {
  clear
  title "Hysteria 2 安装脚本  v${SCRIPT_VERSION}"
  echo -e "  仓库   ${BLUE}https://github.com/JasonZhangDad/install-hy2-script${PLAIN}"
  echo -e "  系统   ${PRETTY_OS:-unknown}"
  echo -e "  权限   root  (uid=$(id -u)  user=$(id -un))"
  echo -e "  状态   $(status_line)"
  hr

  section "安装"
  item 1 "交互式安装"
  hint "逐步选择：证书类型 / 端口 / 密码 / 伪装站 / 端口跳跃"
  item 2 "一键安装 ${YELLOW}（推荐新手）${PLAIN}"
  hint "全默认：自签 ${DEFAULT_SNI} + 随机端口 + 随机密码 + 伪装 ${DEFAULT_MASQUERADE}"

  section "节点"
  item 3 "查看分享链接 / 二维码 ${YELLOW}（断线回来看这个）${PLAIN}"
  item 4 "管理功能（启停 / 改配置 / 自检 / 更新 / 卸载 / 防火墙）"
  item 0 "退出"
  echo
  read -rp "请输入选项 [0-4]: " input
  case "$input" in
    1)
      echo
      yellow "→ 已选择：交互式安装"
      do_install
      pause
      ;;
    2)
      echo
      yellow "→ 已选择：一键安装"
      do_quick_install
      pause
      ;;
    3) show_link; pause ;;
    4) menu_manage ;;
    0) exit 0 ;;
    *) err "无效选项"; sleep 1 ;;
  esac
}

main() {
  # version/help 允许非 root 查看
  case "${1:-}" in
    version|--version|-v)
      echo "install-hy2-script v${SCRIPT_VERSION}"
      exit 0
      ;;
    help|--help|-h)
      cat <<EOF
install-hy2-script v${SCRIPT_VERSION}
【必须 root】安装/管理 Hysteria 2 需要 root 权限。

用法:
  bash install-hy2.sh                 主菜单（交互式 / 一键）
  bash install-hy2.sh interactive     交互式安装
  bash install-hy2.sh onekey          一键安装
  bash install-hy2.sh manage          管理菜单
  bash install-hy2.sh update          更新 Hysteria
  bash install-hy2.sh udp             UDP 缓冲优化
  bash install-hy2.sh uninstall       卸载
  bash install-hy2.sh show            显示配置
  bash install-hy2.sh link            查看分享链接 / 二维码
  bash install-hy2.sh check           连通性自检

推荐运行（root）:
  bash <(curl -fsSL "${REPO_RAW}?t=\$(date +%s)")

非 root 请用 sudo（脚本也会尝试自动 sudo）:
  curl -fsSL "${REPO_RAW}?t=\$(date +%s)" | sudo bash
  sudo bash install-hy2.sh
EOF
      exit 0
      ;;
  esac

  # 本脚本全程需要交互输入。没有可用 TTY 时提前报错，
  # 否则 read 在 set -e 下会让脚本静默退出（exit 1，无任何提示）
  if [[ ! -t 0 ]]; then
    err "未检测到可交互终端：stdin 不是 TTY，且 /dev/tty 不可用。"
    err "请在 SSH 终端中运行，推荐: bash <(curl -fsSL \"${REPO_RAW}?t=\$(date +%s)\")"
    exit 1
  fi

  # 强制 root（非 root 自动 sudo 重跑）
  need_root "$@"
  green "[OK] root 权限检查通过 (uid=$(id -u) user=$(id -un))"
  detect_os

  case "${1:-}" in
    install|interactive)
      yellow "模式：交互式安装"
      do_install
      exit 0
      ;;
    quick|onekey|auto|install-auto)
      yellow "模式：一键安装"
      do_quick_install
      exit 0
      ;;
    manage) menu_manage; exit 0 ;;
    repair|fix) repair_and_start; exit 0 ;;
    uninstall) do_uninstall; exit 0 ;;
    update|update-hy2) update_hysteria; exit 0 ;;
    udp|optimize) menu_udp_optimize; exit 0 ;;
    show) show_conf; exit 0 ;;
    link|url|qr) show_link; exit 0 ;;
    check|diag|diagnose) diagnose_connectivity; exit 0 ;;
  esac

  while true; do
    menu
  done
}

main "$@"
