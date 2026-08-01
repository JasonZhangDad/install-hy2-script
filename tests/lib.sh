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

# 整脚本载入（只去掉末尾那行 main 调用），用于多个函数互相调用的集成测试。
# load_func 抽不出内嵌 JSON 的函数（heredoc 里有顶格的 }），这类只能整份载入。
load_script_no_main() {
  eval "$(grep -v '^main "\$@"$' "$SRC")"
}
