#!/usr/bin/env bash
# 验证 update_script 的下载校验：CDN 错误页 / 截断的传输同样是 HTTP 200，
# 只有完整脚本才允许写进 /usr/local/bin/install-hy2
set -euo pipefail
# shellcheck source=tests/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

load_func update_script

info() { :; }
green() { :; }
yellow() { :; }
err() { echo "        err: $*"; }
nocache_url() { echo "file://${FIXTURE}"; }
# 假 curl：把 fixture 拷到 -o 指定的路径，模拟 HTTP 200
curl() { local out=""; while [[ $# -gt 0 ]]; do [[ "$1" == "-o" ]] && { out="$2"; shift; }; shift; done; cat "$FIXTURE" >"$out"; }
mktemp() { command mktemp "${WORK}/dl.XXXXXX"; }
# 不真的写系统目录，装没装看这行有没有打印
cp()    { echo "INSTALLED"; }
chmod() { :; }

run() { # run <desc> <fixture> <INSTALLED|REJECTED>
  local desc="$1" want="$3"
  FIXTURE="$2"
  local out got="REJECTED"
  out="$(update_script)"
  [[ "$out" == *INSTALLED* ]] && got="INSTALLED"
  if [[ "$got" == "$want" ]]; then
    pass_msg "$desc -> $got"
  else
    fail_msg "$desc -> $got (want $want)"
  fi
}

# 真实完整脚本
run "完整脚本" "$SRC" INSTALLED

# CDN / 反代返回的错误页
printf '<!DOCTYPE html>\n<html><body>404 Not Found</body></html>\n' >"${WORK}/err.html"
run "HTML 错误页" "${WORK}/err.html" REJECTED

# 传输中断：有 shebang，但尾部 main "$@" 缺失
head -200 "$SRC" >"${WORK}/trunc.sh"
run "截断的脚本" "${WORK}/trunc.sh" REJECTED

# 空文件
: >"${WORK}/empty"
run "空文件" "${WORK}/empty" REJECTED

# 有 main "$@" 但没有 shebang
printf 'echo hi\nmain "$@"\n' >"${WORK}/noshebang"
run "缺 shebang" "${WORK}/noshebang" REJECTED

exit $fail
