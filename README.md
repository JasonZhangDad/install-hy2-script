# install-hy2-script

Hysteria 2（hy2）一键安装脚本：交互菜单、多系统支持、自签 / ACME / 自定义证书、端口跳跃、客户端 YAML/JSON/分享链接/二维码。

## 一键运行（推荐）

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/JasonZhangDad/install-hy2-script/main/install-hy2.sh)
```

等价写法：

```bash
curl -fsSL https://raw.githubusercontent.com/JasonZhangDad/install-hy2-script/main/install-hy2.sh | bash
```

> 脚本会在 `curl | bash` 时自动从 `/dev/tty` 读取交互输入。若环境无 TTY，请先下载再执行。

### 下载后执行

```bash
curl -fsSL -o install-hy2.sh https://raw.githubusercontent.com/JasonZhangDad/install-hy2-script/main/install-hy2.sh
chmod +x install-hy2.sh
bash install-hy2.sh
```

## 功能

| 功能 | 说明 |
|------|------|
| **交互式安装** | 逐步选择证书 / 端口 / 密码 / 伪装 / 端口跳跃 |
| **一键安装** | 全默认：自签 `www.bing.com` + 随机端口/密码 + 伪装 bing |
| 卸载 | 使用官方 [get.hy2.sh](https://get.hy2.sh/) 管理二进制 |
| 证书 | ① 自签（默认 `www.bing.com`）② ACME Let's Encrypt ③ 自定义路径 |
| 端口 | 自定义或随机 UDP 端口；可选端口跳跃（iptables DNAT） |
| 认证 | 密码认证（可随机生成） |
| 伪装 | `masquerade` 反向代理伪装网站（默认 `www.bing.com`） |
| 服务管理 | 启动 / 停止 / 重启 |
| 改配置 | 端口、密码、证书、伪装站 |
| **更新 Hysteria** | 官方安装器 `--force` 升到最新版，保留现有配置 |
| **UDP 缓冲优化** | 增大 `rmem/wmem` 等，利于 QUIC 高吞吐；可查看 / 应用 / 移除 |
| 客户端输出 | `/root/hy/hy-client.yaml`、`hy-client.json`、`url.txt`、二维码 |

## 菜单

启动后先选模式：

```
1. 交互式安装     — 逐步配置证书/端口/密码/伪装/端口跳跃
2. 一键安装       — 全默认（自签 bing + 随机端口/密码）
3. 管理功能       — 启停 / 改配置 / 更新 / 卸载 / UDP 优化
0. 退出
```

管理功能子菜单：

```
1. 启动 / 停止 / 重启
2. 修改配置
3. 显示配置
4. 更新 Hysteria 到最新版
5. UDP 缓冲优化
6. 更新本脚本
7. 卸载 Hysteria 2
0. 返回
```

## 支持系统

- Debian / Ubuntu
- CentOS / RHEL / Rocky / Alma / Fedora / Amazon Linux
- Arch（基础支持）

需要 **root**，以及 **systemd**。

## 安装后路径

| 路径 | 说明 |
|------|------|
| `/usr/local/bin/hysteria` | 主程序 |
| `/etc/hysteria/config.yaml` | 服务端配置 |
| `/etc/hysteria/install.meta` | 安装元数据（改配置用） |
| `/etc/hysteria/cert.crt` / `private.key` | 自签证书（默认） |
| `/root/hy/` | 客户端配置与分享链接 |
| `systemctl status hysteria-server` | 服务状态 |

## 防火墙 / 安全组

请放行服务端 **UDP 主端口**。若启用端口跳跃，还需放行对应 **UDP 端口段**。

使用 ACME 申请证书时，申请阶段需放行 **TCP 80**。

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
```

### UDP 优化说明

应用后写入 `/etc/sysctl.d/99-hysteria2.conf`，主要调大：

- `net.core.rmem_max` / `wmem_max`（32MB）
- `net.core.rmem_default` / `wmem_default`（16MB）
- `net.core.netdev_max_backlog`
- `net.ipv4.udp_rmem_min` / `udp_wmem_min`

可在菜单中随时查看、应用或删除该文件。

## 分享链接示例

```text
hysteria2://PASSWORD@SERVER_IP:PORT/?insecure=1&sni=www.bing.com#Hysteria2
```

- 自签默认 `insecure=1`
- ACME 真证书默认 `insecure=0`
- 端口跳跃时附加 `mport=起始-结束`

## 说明

- 二进制安装来源为 Hysteria 官方脚本 `https://get.hy2.sh/`，不经过第三方改包。
- 自签仅适合快速部署；有域名时建议使用 ACME。
- 卸载不会删除本机其它站点使用的 `acme.sh` 与证书，仅清理本脚本生成的 hy2 相关文件。

## License

MIT
