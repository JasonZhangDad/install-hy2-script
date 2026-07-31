#!/usr/bin/env bash
# 测试公共部分：定位被测脚本 + 断言计数

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="${REPO_ROOT}/install-hy2.sh"
[[ -f "$SRC" ]] || { echo "找不到被测脚本: $SRC" >&2; exit 1; }

fail=0

pass_msg() { echo "  PASS  $*"; }
fail_msg() { echo "  FAIL  $*"; fail=1; }

# 从被测脚本里抽出单个函数定义，避免执行 main
load_func() {
  local fn="$1"
  eval "$(awk -v f="^${fn}\\\\(\\\\)" '$0 ~ f, /^}/' "$SRC")"
}
