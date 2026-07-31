#!/usr/bin/env bash
# 验证 TTY 门禁只挡交互入口：只读子命令必须能在无 TTY（cron / 重定向日志）下跑到业务逻辑。
# 做法：在 stdin 非 TTY 的环境下加载脚本全部定义但不跑 main，
# 把 root 检查与各业务入口打桩，再调 main 看是被 require_tty 拦下还是进了业务函数。
set -uo pipefail
# shellcheck source=tests/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

RUNNER="${WORK}/run.sh"
cat >"$RUNNER" <<'EOF'
set -uo pipefail
eval "$(sed 's/^main "\$@"$/: # main disabled/' "$SRC_PATH")"
need_root() { :; }
detect_os() { PRETTY_OS=test; OS_FAMILY=debian; }
green() { :; }
yellow() { :; }
do_install()             { echo REACHED:install; }
do_quick_install()       { echo REACHED:onekey; }
menu_manage()            { echo REACHED:manage; }
repair_and_start()       { echo REACHED:repair; }
do_uninstall()           { echo REACHED:uninstall; }
update_hysteria()        { echo REACHED:update; }
menu_udp_optimize()      { echo REACHED:udp; }
show_conf()              { echo REACHED:show; }
show_link()              { echo REACHED:link; }
diagnose_connectivity()  { echo REACHED:check; }
menu()                   { echo REACHED:menu; exit 0; }
main "$@"
EOF

check() { # check <子命令，空串表示无参数> <REACHED|BLOCKED>
  local arg="${1:-}" want="$2" out rc got="OTHER"
  # </dev/null 保证 stdin 不是 TTY
  # shellcheck disable=SC2086
  out="$(SRC_PATH="$SRC" bash "$RUNNER" $arg 2>&1 </dev/null)"; rc=$?
  [[ "$out" == *REACHED:* ]] && got="REACHED"
  [[ "$out" == *"需要交互输入"* && $rc -eq 1 ]] && got="BLOCKED"
  if [[ "$got" == "$want" ]]; then
    pass_msg "'${arg:-<无参数>}' -> $got"
  else
    fail_msg "'${arg:-<无参数>}' -> $got (want $want) rc=$rc"
    echo "        out: ${out:0:160}"
  fi
}

echo "== 无 TTY 时：只读子命令应放行 =="
for a in show link url qr check diag diagnose repair fix; do
  check "$a" REACHED
done

echo "== 无 TTY 时：交互子命令应拦截 =="
for a in install interactive quick onekey auto manage uninstall update udp optimize; do
  check "$a" BLOCKED
done

echo "== 无 TTY 时：无参数进主菜单应拦截 =="
check "" BLOCKED

exit $fail
