#!/usr/bin/env bash
# 验证新增的证书选项 4 / 5：
#   1. 证书菜单保留原 1~3，新增 4 / 5
#   2. gen_pinned_self_signed 产出私有 CA（CA:TRUE）+ 叶子证书（CA:FALSE + SAN），链可验证
#   3. 固定模式客户端产物带 pinSHA256 / fingerprint / CA，Xray 侧用 pinnedPeerCertSha256
#   4. 兼容产物单独成文件，靠 insecure=1 跳过校验
#   5. ACME 模式（选项4）产物不含 allowInsecure，也不含 insecure=1
#   6. 原自签模式（选项1）行为不变，仍是 insecure=1 且不产生新文件
set -euo pipefail
# shellcheck source=tests/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

load_script_no_main

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# 载入之后再覆盖全局变量与桩函数，否则会被脚本里的定义盖掉
HY_DIR="${WORK}/etc"
HY_CONF="${HY_DIR}/config.yaml"
HY_META="${HY_DIR}/install.meta"
CLIENT_DIR="${WORK}/client"
mkdir -p "$HY_DIR"

fix_hy_permissions()   { :; }
ensure_config_readable() { :; }
get_public_ip()        { echo "203.0.113.9"; }
green() { :; }; info() { :; }; yellow() { :; }; warn() { :; }; red() { :; }
section() { :; }; item() { :; }; itemc() { :; }; hint() { :; }; hr() { :; }

has() { grep -qF "$2" "$1"; }

want()    { # want <desc> <file> <substr>
  if [[ -f "$2" ]] && has "$2" "$3"; then pass_msg "$1"; else fail_msg "$1"; fi
}
wantnot() { # wantnot <desc> <file> <substr>
  if [[ -f "$2" ]] && has "$2" "$3"; then fail_msg "$1"; else pass_msg "$1"; fi
}
wantfile()   { [[ -f "$2" ]] && pass_msg "$1" || fail_msg "$1"; }
wantnofile() { [[ -f "$2" ]] && fail_msg "$1" || pass_msg "$1"; }

json_ok() { # json_ok <desc> <file>
  if ! command -v python3 >/dev/null 2>&1; then
    pass_msg "$1（跳过：无 python3）"
    return 0
  fi
  if python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$2" 2>/dev/null; then
    pass_msg "$1"
  else
    fail_msg "$1"
  fi
}

reset_client_dir() {
  rm -rf "$CLIENT_DIR"
  mkdir -p "$CLIENT_DIR"
}

echo "== 证书菜单 =="
menu_src="$(awk '/^choose_cert\(\)/,/^}/' "$SRC")"
for keep in '自签证书 ${YELLOW}（默认' 'ACME 自动申请（需域名解析到本机）' '自定义证书路径'; do
  if [[ "$menu_src" == *"$keep"* ]]; then
    pass_msg "原选项保留: ${keep:0:20}"
  else
    fail_msg "原选项被改动: ${keep:0:20}"
  fi
done
[[ "$menu_src" == *'item 4 '* ]] && pass_msg "新增选项 4" || fail_msg "缺少选项 4"
[[ "$menu_src" == *'item 5 '* ]] && pass_msg "新增选项 5" || fail_msg "缺少选项 5"
[[ "$menu_src" == *'[1-5]'* ]] && pass_msg "输入范围已扩到 1-5" || fail_msg "输入范围仍是 1-3"

echo
echo "== 选项5：私有 CA + 叶子证书 =="
gen_pinned_self_signed "www.bing.com"

ca_txt="$(openssl x509 -in "${HY_DIR}/ca.crt" -noout -text 2>/dev/null || true)"
leaf_txt="$(openssl x509 -in "${HY_DIR}/cert.crt" -noout -text 2>/dev/null || true)"

[[ "$ca_txt" == *"CA:TRUE"* ]]  && pass_msg "CA 证书 basicConstraints CA:TRUE"  || fail_msg "CA 证书不是 CA:TRUE"
[[ "$leaf_txt" == *"CA:FALSE"* ]] && pass_msg "叶子证书 basicConstraints CA:FALSE" || fail_msg "叶子证书不是 CA:FALSE"
[[ "$leaf_txt" == *"DNS:www.bing.com"* ]] && pass_msg "叶子证书含 SAN DNS:www.bing.com" || fail_msg "叶子证书缺少 SAN"
[[ "$leaf_txt" == *"TLS Web Server Authentication"* ]] && pass_msg "叶子证书含 serverAuth" || fail_msg "叶子证书缺少 serverAuth"

if openssl verify -CAfile "${HY_DIR}/ca.crt" "${HY_DIR}/cert.crt" >/dev/null 2>&1; then
  pass_msg "叶子证书可被私有 CA 验证通过"
else
  fail_msg "叶子证书无法被私有 CA 验证"
fi

real_hex="$(openssl x509 -in "${HY_DIR}/cert.crt" -noout -fingerprint -sha256 | cut -d= -f2 | tr -d ' ')"
[[ "$PIN_SHA256" == "$real_hex" ]] && pass_msg "PIN_SHA256 与 openssl 指纹一致" || fail_msg "PIN_SHA256 不匹配: $PIN_SHA256"
# Xray 的 pinnedPeerCertSha256 走 hex（内部 ReplaceAll(":","") + hex.DecodeString），
# 解码后必须正好 32 字节，否则 Xray 直接报 incorrect length
[[ "$(echo -n "${PIN_SHA256//:/}" | wc -c | tr -d ' ')" == "64" ]] \
  && pass_msg "指纹去冒号后是 64 个 hex 字符（32 字节）" || fail_msg "指纹长度不对"
[[ "$CERT_MODE" == "pinned" ]] && pass_msg "CERT_MODE=pinned" || fail_msg "CERT_MODE=$CERT_MODE"
[[ "$CLIENT_INSECURE" == "false" ]] && pass_msg "CLIENT_INSECURE=false" || fail_msg "CLIENT_INSECURE=$CLIENT_INSECURE"

echo
echo "== 选项5：客户端产物 =="
reset_client_dir
PORT=34567; LAST_PORT=34567; AUTH_PWD="pwd-test-1"; PROXY_SITE="www.bing.com"
HOP_FIRST=""; HOP_LAST=""; BW_UP=""; BW_DOWN=""; XRAY_OUT=1
write_client_files

want    "url.txt 带 pinSHA256"        "${CLIENT_DIR}/url.txt" "pinSHA256=${PIN_SHA256}"
# hysteria 官方客户端设了 pin 也不会关掉标准链校验（Go 先验链再调 VerifyPeerCertificate），
# 私有 CA 必然过不了链校验，所以 hysteria 侧必须 insecure=1，真正的校验交给 pinSHA256。
# 最新版 v2rayN 见到 pinSHA256 会强制 allowInsecure=false 并下发 pinnedPeerCertSha256。
want    "url.txt insecure=1（由 pinSHA256 兜底校验）" "${CLIENT_DIR}/url.txt" "insecure=1"
want    "hy-client.yaml insecure true" "${CLIENT_DIR}/hy-client.yaml" "insecure: true"
want    "hy-client.yaml 带 pinSHA256" "${CLIENT_DIR}/hy-client.yaml" "pinSHA256: ${PIN_SHA256}"
want    "hy-client.json 带 pinSHA256" "${CLIENT_DIR}/hy-client.json" "\"pinSHA256\": \"${PIN_SHA256}\""
json_ok "hy-client.json 是合法 JSON"  "${CLIENT_DIR}/hy-client.json"
want    "clash-meta.yaml 带 fingerprint" "${CLIENT_DIR}/clash-meta.yaml" "fingerprint: \"${PIN_SHA256}\""
wantnot "clash-meta.yaml 不跳过校验"  "${CLIENT_DIR}/clash-meta.yaml" "skip-cert-verify: true"
want    "sing-box.json 内嵌 CA"       "${CLIENT_DIR}/sing-box.json" "\"certificate\""
want    "sing-box.json insecure false" "${CLIENT_DIR}/sing-box.json" "\"insecure\": false"
json_ok "sing-box.json 是合法 JSON"   "${CLIENT_DIR}/sing-box.json"

# Xray 已原生支持 hysteria2：protocol=hysteria + network=hysteria + hysteriaSettings
want    "xray.json 是 hysteria outbound" "${CLIENT_DIR}/xray-outbound.json" "\"protocol\": \"hysteria\""
want    "xray.json network=hysteria"  "${CLIENT_DIR}/xray-outbound.json" "\"network\": \"hysteria\""
want    "xray.json 带 auth"           "${CLIENT_DIR}/xray-outbound.json" "\"auth\": \"${AUTH_PWD}\""
want    "xray.json 用 pinnedPeerCertSha256" "${CLIENT_DIR}/xray-outbound.json" "\"pinnedPeerCertSha256\": \"${PIN_SHA256}\""
wantnot "xray.json 不含 allowInsecure（新版 Xray 会直接报错）" "${CLIENT_DIR}/xray-outbound.json" "allowInsecure"
json_ok "xray.json 是合法 JSON"       "${CLIENT_DIR}/xray-outbound.json"
wantfile "CA 证书已复制给客户端"      "${CLIENT_DIR}/ca.crt"

echo
echo "== 选项5：兼容产物（必须单独成文件并标注）=="
want    "url-compat.txt insecure=1"   "${CLIENT_DIR}/url-compat.txt" "insecure=1"
want    "clash-meta-compat.yaml 跳过校验" "${CLIENT_DIR}/clash-meta-compat.yaml" "skip-cert-verify: true"
want    "clash-meta-compat.yaml 有兼容标注" "${CLIENT_DIR}/clash-meta-compat.yaml" "仅用于兼容客户端"
want    "sing-box-compat.json insecure true" "${CLIENT_DIR}/sing-box-compat.json" "\"insecure\": true"
json_ok "sing-box-compat.json 是合法 JSON" "${CLIENT_DIR}/sing-box-compat.json"

echo
echo "== 选项4：ACME 正式证书产物 =="
reset_client_dir
CERT_MODE="acme"; CLIENT_INSECURE="false"; HY_DOMAIN="hy2.example.com"; XRAY_OUT=1
write_client_files

want    "url.txt insecure=0"            "${CLIENT_DIR}/url.txt" "insecure=0"
wantnot "url.txt 不含 insecure=1"       "${CLIENT_DIR}/url.txt" "insecure=1"
wantnot "url.txt 不带 pinSHA256"        "${CLIENT_DIR}/url.txt" "pinSHA256"
want    "hy-client.yaml insecure false" "${CLIENT_DIR}/hy-client.yaml" "insecure: false"
wantnot "sing-box.json 不内嵌 CA"       "${CLIENT_DIR}/sing-box.json" "\"certificate\""
want    "sing-box.json insecure false"  "${CLIENT_DIR}/sing-box.json" "\"insecure\": false"
json_ok "sing-box.json 是合法 JSON"     "${CLIENT_DIR}/sing-box.json"
want    "clash-meta.yaml 不跳过校验"    "${CLIENT_DIR}/clash-meta.yaml" "skip-cert-verify: false"
wantfile "生成 Xray outbound"           "${CLIENT_DIR}/xray-outbound.json"
want    "xray.json 是 hysteria outbound" "${CLIENT_DIR}/xray-outbound.json" "\"protocol\": \"hysteria\""
wantnot "xray.json 不含 allowInsecure"  "${CLIENT_DIR}/xray-outbound.json" "allowInsecure"
wantnot "正式证书不做证书固定"          "${CLIENT_DIR}/xray-outbound.json" "pinnedPeerCertSha256"
json_ok "xray.json 是合法 JSON"         "${CLIENT_DIR}/xray-outbound.json"
wantnofile "ACME 模式不产生兼容链接"    "${CLIENT_DIR}/url-compat.txt"

echo
echo "== 回归：选项1 自签行为不变 =="
reset_client_dir
CERT_MODE="self"; CLIENT_INSECURE="true"; HY_DOMAIN="www.bing.com"; XRAY_OUT=""
write_client_files

want    "url.txt insecure=1"          "${CLIENT_DIR}/url.txt" "insecure=1"
wantnot "url.txt 不带 pinSHA256"      "${CLIENT_DIR}/url.txt" "pinSHA256"
want    "hy-client.yaml insecure true" "${CLIENT_DIR}/hy-client.yaml" "insecure: true"
wantnot "hy-client.yaml 无 pinSHA256" "${CLIENT_DIR}/hy-client.yaml" "pinSHA256"
want    "clash-meta.yaml 跳过校验"    "${CLIENT_DIR}/clash-meta.yaml" "skip-cert-verify: true"
wantnot "sing-box.json 不内嵌 CA"     "${CLIENT_DIR}/sing-box.json" "\"certificate\""
json_ok "sing-box.json 是合法 JSON"   "${CLIENT_DIR}/sing-box.json"
wantnofile "不生成 Xray 配置"         "${CLIENT_DIR}/xray-outbound.json"
wantnofile "不生成兼容链接"           "${CLIENT_DIR}/url-compat.txt"

echo
echo "== 切换证书方式后，上一套产物被清理（里面是旧密码旧指纹）=="
reset_client_dir
CERT_MODE="pinned"; CLIENT_INSECURE="false"; HY_DOMAIN="www.bing.com"; XRAY_OUT=1
CA_PATH="${HY_DIR}/ca.crt"
cert_fingerprints "${HY_DIR}/cert.crt"
write_client_files
wantfile "先有兼容链接" "${CLIENT_DIR}/url-compat.txt"
wantfile "先有 Xray 配置" "${CLIENT_DIR}/xray-outbound.json"

# 不清目录，直接切回自签，模拟「管理 → 修改证书」
CERT_MODE="self"; CLIENT_INSECURE="true"; XRAY_OUT=""
write_client_files
wantnofile "切回自签后删掉兼容链接"   "${CLIENT_DIR}/url-compat.txt"
wantnofile "切回自签后删掉兼容 mihomo" "${CLIENT_DIR}/clash-meta-compat.yaml"
wantnofile "切回自签后删掉兼容 sing-box" "${CLIENT_DIR}/sing-box-compat.json"
wantnofile "切回自签后删掉 CA 证书"    "${CLIENT_DIR}/ca.crt"
wantnofile "切回自签后删掉 Xray 配置"  "${CLIENT_DIR}/xray-outbound.json"

echo
echo "== 回归：切回自签后 meta 里的旧指纹被清除 =="
[[ "$(meta_get pin_sha256)" == "" ]] && pass_msg "meta pin_sha256 已清空" || fail_msg "meta 残留旧指纹: $(meta_get pin_sha256)"
[[ "$(meta_get xray_out)" == "" ]] && pass_msg "meta xray_out 已清空" || fail_msg "meta 残留 xray_out"

exit $fail
