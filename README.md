# install-hy2-script

Hysteria 2（hy2）一键安装脚本：交互菜单、多系统支持、自签 / ACME / 自定义证书、端口跳跃、客户端 YAML/JSON/分享链接/二维码。

## 权限要求（必须 root）

本脚本 **必须以 root 运行**。安装二进制、写 `/etc`、操作 systemd、改防火墙、sysctl 都需要 root。

| 方式 | 命令 |
|------|------|
| 已是 root | `bash <(curl -fsSL https://raw.githubusercontent.com/JasonZhangDad/install-hy2-script/main/install-hy2.sh)` |
| 普通用户 | `curl -fsSL https://raw.githubusercontent.com/JasonZhangDad/install-hy2-script/main/install-hy2.sh \| sudo bash` |
| 先提权 | `sudo -i` 后再执行脚本 |

非 root 时：若本地文件执行且存在 `sudo`，会尝试自动 `sudo` 重跑；`curl \| bash` 场景请直接加 `sudo bash`。

## 一键运行（推荐）

```bash
# root
bash <(curl -fsSL https://raw.githubusercontent.com/JasonZhangDad/install-hy2-script/main/install-hy2.sh)

# 非 root
curl -fsSL https://raw.githubusercontent.com/JasonZhangDad/install-hy2-script/main/install-hy2.sh | sudo bash
```

> 脚本会在 `curl | bash` 时自动从 `/dev/tty` 读取交互输入。若环境无 TTY，请先下载再执行。

### 下载后执行

```bash
curl -fsSL -o install-hy2.sh https://raw.githubusercontent.com/JasonZhangDad/install-hy2-script/main/install-hy2.sh
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
| 改配置 | ✅ | 端口、密码、证书、伪装站 |
| **更新 Hysteria** | ✅ | 官方 `--force`，保留配置 |
| **UDP 缓冲优化** | ✅ | sysctl `rmem/wmem` 等 |
| **防火墙自动识别** | ✅ | ufw → firewalld → iptables，自动放行 UDP |
| 客户端输出 | ✅ | `/root/hy/` 下 YAML / JSON / url / 二维码 |
| 更新本脚本 | ✅ | 写入 `/usr/local/bin/install-hy2` |

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
6. 自动放行防火墙端口（识别 ufw / firewalld / iptables）
7. 更新本脚本
8. 卸载 Hysteria 2
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

ACME 申请证书时会额外按同一逻辑放行 **TCP 80**。  
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
