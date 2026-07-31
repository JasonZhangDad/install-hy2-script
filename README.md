# install-hy2-script

Hysteria 2（hy2）一键安装脚本：交互菜单、多系统支持、自签 / ACME / 自定义证书、端口跳跃、客户端 YAML/JSON/分享链接/二维码。

## 权限要求（必须 root）✅

本脚本 **强制 root**。启动时会检查 `uid==0`：

- 已是 root → 继续  
- 非 root → **自动 `sudo` 提权重跑**（本地文件 / `curl|bash` / 进程替换均支持）  
- 无 sudo 或提权失败 → 退出并提示正确命令  

需要 root 的原因：写 `/usr/local/bin`、`/etc/hysteria`、systemd、防火墙、sysctl、`/root/hy`。

| 方式 | 命令 |
|------|------|
| 已是 root | `bash <(curl -fsSL "https://raw.githubusercontent.com/JasonZhangDad/install-hy2-script/main/install-hy2.sh?t=$(date +%s)")` |
| 普通用户（推荐） | `curl -fsSL "https://raw.githubusercontent.com/JasonZhangDad/install-hy2-script/main/install-hy2.sh?t=$(date +%s)" \| sudo bash` |
| 先提权 | `sudo -i` 后再执行脚本 |
| 本地文件 | `sudo bash install-hy2.sh` |

## 一键运行（推荐）

```bash
# root
bash <(curl -fsSL "https://raw.githubusercontent.com/JasonZhangDad/install-hy2-script/main/install-hy2.sh?t=$(date +%s)")

# 非 root（推荐写法）
curl -fsSL "https://raw.githubusercontent.com/JasonZhangDad/install-hy2-script/main/install-hy2.sh?t=$(date +%s)" | sudo bash
```

> 命令里的 `?t=$(date +%s)` 是**防 CDN 缓存**：`raw.githubusercontent.com` 有约 5 分钟缓存，
> 不加参数可能拉到旧版本。脚本的「更新本脚本」和自动提权重下也都已内置该处理。

> 脚本会在 `curl | bash` 时自动从 `/dev/tty` 读取交互输入。若环境无 TTY，需要交互的入口会**明确报错**而不是静默退出；
> `show` / `link` / `check` / `repair` 这类只读子命令不需要 TTY，可正常在 cron 中运行。

### 下载后执行

```bash
curl -fsSL -o install-hy2.sh "https://raw.githubusercontent.com/JasonZhangDad/install-hy2-script/main/install-hy2.sh?t=$(date +%s)"
chmod +x install-hy2.sh
sudo bash install-hy2.sh
```

## 功能一览

| 功能 | 需要 root | 说明 |
|------|:---------:|------|
| **交互式安装** | ✅ | 逐步选择证书 / 端口 / 密码 / 伪装 / 端口跳跃 |
| **一键安装** | ✅ | 全默认：自签 `www.bing.com` + 随机端口/密码 + 伪装 bing |
| 卸载 | ✅ | 官方 [get.hy2.sh](https://get.hy2.sh/) 卸二进制 + 清配置 |
| 证书（自签 / ACME / 自定义） | ✅ | 默认自签 `www.bing.com`；ACME 需域名 |
| 端口 / 端口跳跃 | ✅ | 随机或自定义 UDP；跳跃用 iptables DNAT |
| 认证密码 | ✅ | 手输或随机 |
| 伪装站 masquerade | ✅ | 默认 `www.bing.com` |
| 服务启停重启 | ✅ | systemd `hysteria-server` |
| 改配置 | ✅ | 端口、密码、证书、伪装站、带宽 |
| **带宽 / 加速（可选）** | ✅ | 填带宽切 Brutal，不填用 BBR；**安装时不询问**，按需在菜单开启 |
| **更新 Hysteria** | ✅ | 官方 `--force`，保留配置 |
| **UDP 缓冲优化** | ✅ | sysctl `rmem/wmem` 等 |
| **防火墙自动识别** | ✅ | ufw → firewalld → iptables，自动放行 UDP |
| 客户端输出 | ✅ | `/root/hy/` 下 YAML / JSON / url / 二维码 / Clash Meta / sing-box |
| **连通性自检** | ✅ | 安装后自动跑一次，指出到底哪一层不通 |
| **查看链接 / 二维码** | ✅ | 断线回来直接看，主菜单第 3 项 |
| 更新本脚本 | ✅ | 写入 `/usr/local/bin/install-hy2` |

## 菜单

启动后先选模式：

```
1. 交互式安装          — 逐步配置证书/端口/密码/伪装/端口跳跃
2. 一键安装            — 全默认（自签 bing + 随机端口/密码）
3. 查看分享链接 / 二维码 — 断线回来直接看，不用翻配置
4. 管理功能            — 启停 / 改配置 / 自检 / 更新 / 卸载
0. 退出
```

管理功能子菜单：

```
── 节点 ──
 1. 查看分享链接 / 二维码
 2. 显示完整配置（YAML / JSON / 链接 / 二维码）
 3. 修改配置（端口 / 密码 / 证书 / 伪装站 / 带宽）
── 服务 ──
 4. 启动 / 停止 / 重启
 5. 连通性自检（连不上先跑这个）
 6. 修复权限并启动（permission denied 用这个）
── 维护 ──
 7. 自动放行防火墙端口（识别 ufw / firewalld / iptables）
 8. UDP 缓冲优化
 9. 更新 Hysteria 到最新版
10. 更新本脚本
── 其它 ──
11. 卸载 Hysteria 2
 0. 返回
```

「修改配置」子菜单：

```
1. 修改端口 / 端口跳跃
2. 修改密码
3. 修改证书
4. 修改伪装网站
5. 带宽 / 加速（Brutal，可选，默认 BBR）
0. 返回
```

### 防火墙策略

安装或改端口后，脚本会 **自动检测** 本机防火墙并放行 hy2 的 UDP 端口：

| 检测结果 | 使用命令 |
|----------|----------|
| ufw 状态为 active | `ufw allow <port>/udp` |
| firewalld 在运行 | `firewall-cmd --permanent --add-port=.../udp` |
| 其它且有 iptables | `iptables -I INPUT -p udp --dport ... -j ACCEPT`（并尝试持久化） |
| 都没有 | 仅提示去云安全组放行 |

ACME 申请证书时会额外按同一逻辑**临时**放行 **TCP 80**，申请结束（无论成败）立即收回；
若 80 在申请前本来就是放行的，则原样保留不动。
续期时 acme.sh 同样走 standalone 需要 80，脚本已把「开 80 / 关 80」写成
`--pre-hook` / `--post-hook` 存进域名配置，由 acme.sh 在续期时自行临时开关，
因此**平时你在防火墙里看不到 80 是正常的**。

**云厂商安全组**仍需在网页控制台单独放行（脚本改不了）。

## 支持系统

- Debian / Ubuntu
- CentOS / RHEL / Rocky / Alma / Fedora / Amazon Linux
- Arch（基础支持）

需要 **root**，以及 **systemd**。

## 安装后路径

| 路径 | 说明 |
|------|------|
| `/usr/local/bin/hysteria` | 主程序 |
| `/etc/hysteria/config.yaml` | 服务端配置（`600`，含明文密码） |
| `/etc/hysteria/install.meta` | 安装元数据（`600`，含明文密码） |
| `/etc/hysteria/cert.crt` / `private.key` | 自签证书（默认） |
| `/root/hy/` | 客户端目录（`700`，内含密码的文件均为 `600`） |
| `/root/hy/hy-client.yaml` / `.json` | Hysteria 官方客户端配置 |
| `/root/hy/clash-meta.yaml` | Clash Meta / mihomo 片段 |
| `/root/hy/sing-box.json` | sing-box outbound 片段 |
| `/root/hy/url.txt` / `url-qr.png` | 分享链接与二维码 |
| `systemctl status hysteria-server` | 服务状态 |

## 防火墙 / 安全组

请放行服务端 **UDP 主端口**。若启用端口跳跃，还需放行对应 **UDP 端口段**。

使用 ACME 申请证书时，申请阶段需放行 **TCP 80**（脚本自动放行并在申请后收回，
续期由 acme.sh hook 临时开关，详见上文「防火墙自动放行」）。

## 命令行快捷参数

```bash
bash install-hy2.sh                 # 主菜单：选 交互式 / 一键
bash install-hy2.sh interactive     # 直接进交互式安装
bash install-hy2.sh onekey          # 直接进一键安装
bash install-hy2.sh manage          # 管理菜单
bash install-hy2.sh update          # 更新 Hysteria
bash install-hy2.sh udp             # UDP 缓冲优化
bash install-hy2.sh uninstall       # 卸载
bash install-hy2.sh show            # 显示配置
bash install-hy2.sh link            # 查看分享链接 / 二维码
bash install-hy2.sh check           # 连通性自检
bash install-hy2.sh repair          # 修复权限并启动
```

其中 **`show` / `link` / `check` / `repair` 不需要交互终端**，可放进 cron 或把输出重定向到日志：

```bash
# 每天记录一次自检结果（该路径由菜单「更新本脚本」写入，也可直接用本地文件路径）
0 4 * * * /usr/local/bin/install-hy2 check >> /var/log/hy2-check.log 2>&1
```

其余子命令会读取输入，无可用 TTY 时会明确报错退出。

### UDP 优化说明

应用后写入 `/etc/sysctl.d/99-hysteria2.conf`，主要调大：

- `net.core.rmem_max` / `wmem_max`（32MB）
- `net.core.rmem_default` / `wmem_default`（16MB）
- `net.core.netdev_max_backlog`
- `net.ipv4.udp_rmem_min` / `udp_wmem_min`

可在菜单中随时查看、应用或删除该文件。

### 带宽 / 加速（Brutal）说明

**可选功能，安装时不会询问，默认使用 BBR**，需要时进「管理 → 修改配置 → 5」开启。

| 模式 | 触发条件 | 行为 | 适用 |
|------|----------|------|------|
| **BBR** | 不填带宽（默认） | 自适应探测，丢包时主动退让 | 线路质量好、丢包低 |
| **Brutal** | 填写上下行带宽 | 按固定速率发送，无视丢包 | 跨境高丢包 / 延迟抖动大 |

开启后脚本会同时写入服务端 `config.yaml` 与全部客户端配置（含分享链接的
`upmbps` / `downmbps` 参数），**不需要手动改任何文件**；后续改端口、改密码也不会丢失该设置。

调参要点：

- 填**本地宽带的真实速率**并下调 10~20%，例如实测 100M 下行填 `80`
- **填太高会自伤式丢包**，比不填更差；**填太低会卡住发送窗口**，导致握手超时
- 判断优劣时**先看连接成功率，再看延迟数字** —— 超时率高的配置即使延迟好看也要淘汰
- 回车留空即可关闭 Brutal，退回 BBR

> Brutal 只能压平抖动、减少排队延迟，**降不了物理延迟**。基础 RTT 由服务器地理位置决定，
> 跨洲线路想真正提速只能换机房区域。

### 连通性自检说明

**安装完会自动跑一次**，也可随时用「管理 → 5」或 `bash install-hy2.sh check` 手动执行。
只读检查，不改任何配置。

检查项：

| 检查 | 说明 |
|------|------|
| 服务实际监听端口 | 与配置比对，避免"防火墙开了另一个端口" |
| 本机防火墙 | ufw / firewalld / iptables 是否已放行该 UDP 端口 |
| 网卡地址是否私网 | `10.x` / `172.16-31.x` / `192.168.x` / CGNAT `100.64/10` |
| 出站地址 | 与网卡地址比对，判断是否在 NAT 之后 |
| 云元数据入站公网 IP | 支持 Azure / AWS / GCP / 阿里云 / 腾讯云 |
| 服务端自测 | 本机起客户端走环回，把"服务端问题"和"网络问题"分开 |

**最有价值的是「入站公网 IP」那一项** —— 机器只有出站 SNAT 而没有入站公网地址时，
脚本以前会照常生成一个**看起来正常但永远连不上**的链接，现在会直接报 FAIL 并说明原因。

> 云安全组（Azure NSG / 阿里云安全组等）需要 API 密钥才能操作，脚本改不了，
> 自检末尾会提醒你去控制台放行。

## 分享链接示例

```text
hysteria2://PASSWORD@SERVER_IP:PORT/?insecure=1&sni=www.bing.com#Hysteria2
```

- 自签默认 `insecure=1`
- ACME 真证书默认 `insecure=0`
- 端口跳跃时附加 `mport=起始-结束`
- 启用 Brutal 时附加 `upmbps=10&downmbps=30`（多数客户端可识别）

## 安全说明

- 含明文密码的文件（`config.yaml`、`install.meta`、`/root/hy/*`）一律 `600`，
  目录 `700`，**不会让同机其它本地用户读到节点密码**
- 服务以 `User=hysteria` 运行时，配置会 `chown` 给该用户，属主 `600` 即可读；
  极端环境下会自动降级到 `640 (root:hysteria)`，**不会降到全局可读的 644**
- 密码限制为 `A-Za-z0-9._~-`：这些字符在 YAML 和 URL 中均无歧义，
  避免 `: ` 写坏配置、`*` 被当成 YAML alias
- 脚本下载临时文件一律使用 `mktemp` 随机名，避免 `/tmp` 下的软链抢占

## 开发 / 测试

```bash
bash tests/run.sh
```

纯桩测试，**不碰系统**（防火墙命令、`curl`、文件写入、各业务入口全部打桩），
在任意机器上都能跑，不需要 root。覆盖：

| 文件 | 覆盖内容 |
|------|----------|
| `tests/test-firewall-tcp.sh` | ACME 借用 TCP 80 的开关逻辑（ufw / firewalld / iptables / 无防火墙） |
| `tests/test-update-script.sh` | 自更新的下载校验：CDN 错误页、截断传输、空文件一律拒装 |
| `tests/test-cli-tty.sh` | 各子命令的 TTY 门禁：只读命令放行、交互命令拦截 |

`tests/run.sh` 会先跑一次 `bash -n` 语法检查，再依次执行 `tests/test-*.sh`。

## 说明

- 二进制安装来源为 Hysteria 官方脚本 `https://get.hy2.sh/`，不经过第三方改包。
- 自签仅适合快速部署；有域名时建议使用 ACME。
- ACME 证书续期由 acme.sh 自己的 cron 完成；脚本已在 `--reloadcmd` 中带上
  `chown` / `chmod`，避免续期后证书属主变回 root 导致服务起不来。
- 卸载不会删除本机其它站点使用的 `acme.sh` 与证书，仅清理本脚本生成的 hy2 相关文件。

## License

MIT
