#!/usr/bin/env bash
# 跑全部测试: bash tests/run.sh
set -uo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"
fail=0

echo "=== 语法检查 ==="
if bash -n ../install-hy2.sh; then
  echo "  PASS  install-hy2.sh 语法正确"
else
  echo "  FAIL  install-hy2.sh 语法错误"
  fail=1
fi

for t in test-*.sh; do
  echo
  echo "=== $t ==="
  bash "$t" || fail=1
done

echo
if [[ $fail -eq 0 ]]; then
  echo "全部通过"
else
  echo "存在失败用例"
fi
exit $fail
