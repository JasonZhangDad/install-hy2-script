#!/usr/bin/env bash
# 验证 ACME 借用 TCP 80 的开关逻辑：
#   1. is_firewall_tcp_open 对四种防火墙后端的判定
#   2. close_firewall_tcp 在任何后端下都返回 0
#   3. install_acme_cert 里那段新增代码在 set -euo pipefail 下不会误触发 errexit
set -euo pipefail
# shellcheck source=tests/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

load_func is_firewall_tcp_open
load_func close_firewall_tcp

green() { :; }
persist_iptables() { return 1; }

check() { # check <desc> <expected rc> <cmd...>
  local desc="$1" want="$2"; shift 2
  local rc=0
  "$@" || rc=$?
  if [[ "$rc" -eq "$want" ]]; then
    pass_msg "$desc"
  else
    fail_msg "$desc (want rc=$want got rc=$rc)"
  fi
}

echo "== is_firewall_tcp_open =="

detect_firewall() { echo none; }
check "无防火墙 -> 未放行" 1 is_firewall_tcp_open 80

detect_firewall() { echo ufw; }
ufw() { printf 'Status: active\n\nTo                         Action      From\n--                         ------      ----\n80/tcp                     ALLOW       Anywhere\n'; }
check "ufw 已放行 80 -> 已放行" 0 is_firewall_tcp_open 80
check "ufw 未放行 8080 -> 未放行" 1 is_firewall_tcp_open 8080
ufw() { printf 'Status: active\n\n443/udp                    ALLOW       Anywhere\n'; }
check "ufw 无 80 规则 -> 未放行" 1 is_firewall_tcp_open 80

detect_firewall() { echo firewalld; }
firewall-cmd() { echo "80/tcp 443/udp"; }
check "firewalld 含 80/tcp -> 已放行" 0 is_firewall_tcp_open 80
check "firewalld 无 8080/tcp -> 未放行" 1 is_firewall_tcp_open 8080

detect_firewall() { echo iptables; }
iptables() { printf -- '-P INPUT DROP\n-A INPUT -p tcp -m tcp --dport 80 -j ACCEPT\n'; }
check "iptables 含 80 ACCEPT -> 已放行" 0 is_firewall_tcp_open 80
check "iptables 无 8080 -> 未放行" 1 is_firewall_tcp_open 8080
iptables() { printf -- '-P INPUT DROP\n-A INPUT -p udp -m udp --dport 443 -j ACCEPT\n'; }
check "iptables 无 80 规则 -> 未放行" 1 is_firewall_tcp_open 80

echo "== close_firewall_tcp 在各后端下均返回 0（否则会触发 errexit）=="
for be in none ufw firewalld iptables; do
  eval "detect_firewall() { echo $be; }"
  ufw() { return 1; }
  firewall-cmd() { return 1; }
  iptables() { return 1; }
  check "close_firewall_tcp on $be" 0 close_firewall_tcp 80
done

echo "== 调用点的 errexit 安全性（复刻 install_acme_cert 片段）=="
# 回归：曾经写成 `is_firewall_tcp_open 80 && had_tcp80=1`，
# 该语句在无防火墙时整体返回 1，errexit 下会让安装流程直接退出
detect_firewall() { echo none; }
seq_under_errexit() {
  local had_tcp80=0
  if is_firewall_tcp_open 80; then had_tcp80=1; fi
  local post_hook=""
  if [[ $had_tcp80 -eq 0 ]]; then
    close_firewall_tcp 80
    if [[ -n "$post_hook" ]]; then echo hook; fi
  fi
  return 0
}
check "未知防火墙时整段不退出" 0 seq_under_errexit

exit $fail
