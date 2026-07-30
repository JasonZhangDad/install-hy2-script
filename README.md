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
| 安装 / 卸载 | 使用官方 [get.hy2.sh](https://get.hy2.sh/) 安装二进制 |
| 证书 | ① 自签（默认 `www.bing.com`）② ACME Let's Encrypt ③ 自定义路径 |
| 端口 | 自定义或随机 UDP 端口；可选端口跳跃（iptables DNAT） |
| 认证 | 密码认证（可随机生成） |
| 伪装 | `masquerade` 反向代理伪装网站（默认 `www.bing.com`） |
| 服务管理 | 启动 / 停止 / 重启 |
| 改配置 | 端口、密码、证书、伪装站 |
| 客户端输出 | `/root/hy/hy-client.yaml`、`hy-client.json`、`url.txt`、二维码 |

## 菜单

```
1. 安装 Hysteria 2
2. 卸载 Hysteria 2
3. 启动 / 停止 / 重启
4. 修改配置（端口/密码/证书/伪装站）
5. 显示配置（YAML / JSON / 链接 / 二维码）
6. 更新本脚本
0. 退出
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
bash install-hy2.sh install     # 直接走安装向导
bash install-hy2.sh uninstall   # 卸载
bash install-hy2.sh show        # 显示配置
bash install-hy2.sh version
```

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
