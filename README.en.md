# install-hy2-script

[简体中文](README.md) | **English**

One-command installer for Hysteria 2 (hy2): interactive menu, multi-distro support, self-signed / ACME / custom / domain-issued certificates / SHA-256 certificate pinning, port hopping, and client configs for Hysteria2, sing-box, mihomo and Xray plus share links and QR codes.

## Root required ✅

This script **requires root**. It checks `uid == 0` at startup:

- Already root → continue
- Not root → **automatically re-executes itself through `sudo`** (works for a local file, `curl | bash`, and process substitution)
- No sudo, or escalation failed → exit with the correct command to run

Root is needed to write `/usr/local/bin`, `/etc/hysteria`, systemd units, firewall rules, sysctl and `/root/hy`.

| Situation | Command |
|-----------|---------|
| Already root | `bash <(curl -fsSL "https://raw.githubusercontent.com/JasonZhangDad/install-hy2-script/main/install-hy2.sh?t=$(date +%s)")` |
| Regular user (recommended) | `curl -fsSL "https://raw.githubusercontent.com/JasonZhangDad/install-hy2-script/main/install-hy2.sh?t=$(date +%s)" \| sudo bash` |
| Escalate first | `sudo -i`, then run the script |
| Local file | `sudo bash install-hy2.sh` |

## Quick start (recommended)

```bash
# as root
bash <(curl -fsSL "https://raw.githubusercontent.com/JasonZhangDad/install-hy2-script/main/install-hy2.sh?t=$(date +%s)")

# as a regular user (recommended form)
curl -fsSL "https://raw.githubusercontent.com/JasonZhangDad/install-hy2-script/main/install-hy2.sh?t=$(date +%s)" | sudo bash
```

> The `?t=$(date +%s)` part **defeats CDN caching**: `raw.githubusercontent.com` caches for
> roughly 5 minutes, so without it you may fetch a stale version. The script's own
> "update this script" action and the sudo re-download both do the same thing internally.

> When run via `curl | bash`, the script reads interactive input from `/dev/tty`. If no TTY is
> available, entry points that need input **fail loudly** instead of exiting silently;
> the read-only subcommands `show` / `link` / `check` / `repair` need no TTY and run fine under cron.

### Download, then run

```bash
curl -fsSL -o install-hy2.sh "https://raw.githubusercontent.com/JasonZhangDad/install-hy2-script/main/install-hy2.sh?t=$(date +%s)"
chmod +x install-hy2.sh
sudo bash install-hy2.sh
```

## Features

| Feature | Root | Notes |
|---------|:----:|-------|
| **Interactive install** | ✅ | Step through certificate / port / password / masquerade / port hopping |
| **One-key install** | ✅ | All defaults: self-signed `www.bing.com` + random port/password + bing masquerade |
| Uninstall | ✅ | Official [get.hy2.sh](https://get.hy2.sh/) removes the binary, script cleans the config |
| Certificates (self-signed / ACME / custom) | ✅ | Defaults to self-signed `www.bing.com`; ACME needs a domain |
| **Domain + ACME real certificate (option 4)** | ✅ | DNS check + Cloudflare grey-cloud warning + auto renewal; `insecure=0`, emits no skip-verification field |
| **Self-signed + SHA-256 pinning (option 5)** | ✅ | Private CA issues the leaf certificate, clients verify by fingerprint; works with the latest Xray / v2rayN that removed `allowInsecure` |
| Port / port hopping | ✅ | Random or custom UDP; hopping via iptables DNAT |
| Auth password | ✅ | Typed or random |
| Masquerade site | ✅ | Defaults to `www.bing.com` |
| Service start/stop/restart | ✅ | systemd `hysteria-server` |
| Change config | ✅ | Port, password, certificate, masquerade site, bandwidth |
| **Bandwidth / acceleration (optional)** | ✅ | Setting bandwidth switches to Brutal, leaving it empty uses BBR; **never asked during install**, enable from the menu when needed |
| **Update Hysteria** | ✅ | Official `--force`, config preserved |
| **UDP buffer tuning** | ✅ | sysctl `rmem/wmem` and friends |
| **Firewall auto-detection** | ✅ | ufw → firewalld → iptables, opens the UDP port automatically |
| Client output | ✅ | YAML / JSON / url / QR / Clash Meta / sing-box / Xray outbound under `/root/hy/` |
| **Connectivity self-check** | ✅ | Runs automatically after install and tells you exactly which layer is broken |
| **Show link / QR** | ✅ | Main menu item 3, for when you come back after a disconnect |
| Update this script | ✅ | Installs to `/usr/local/bin/install-hy2` |

## Menus

Pick a mode at startup:

```
1. Interactive install   — step through certificate/port/password/masquerade/port hopping
2. One-key install       — all defaults (self-signed bing + random port/password)
3. Show share link / QR  — come back after a disconnect, no need to dig through configs
4. Management            — start/stop, change config, self-check, update, uninstall
0. Exit
```

Management submenu:

```
── Node ──
 1. Show share link / QR
 2. Show full config (YAML / JSON / link / QR)
 3. Change config (port / password / certificate / masquerade / bandwidth)
── Service ──
 4. Start / stop / restart
 5. Connectivity self-check (run this first when it won't connect)
 6. Fix permissions and start (use this on "permission denied")
── Maintenance ──
 7. Open firewall port automatically (detects ufw / firewalld / iptables)
 8. UDP buffer tuning
 9. Update Hysteria to the latest version
10. Update this script
── Other ──
11. Uninstall Hysteria 2
 0. Back
```

"Change config" submenu:

```
1. Change port / port hopping
2. Change password
3. Change certificate
4. Change masquerade site
5. Bandwidth / acceleration (Brutal, optional, BBR by default)
0. Back
```

### Certificate modes (shown during install and when changing the certificate)

```
1. Self-signed certificate (default, SNI=www.bing.com)
2. ACME automatic issuance (domain must resolve to this host)
3. Custom certificate paths
4. Own domain + ACME real certificate    ← recommended, for the latest Xray
5. Self-signed + SHA-256 pinning         ← no domain needed, for the latest Xray
```

Options 1–3 behave exactly as before. Options 4 and 5 were added because **the latest Xray
removed `allowInsecure`**; both produce a link you can **paste directly into a client**, with
certificates and firewall ports handled end to end.

#### 4. Own domain + ACME real certificate (recommended)

- Checks that the domain resolves to this host's public IP, and asks for confirmation on a mismatch
- Explicitly warns that Cloudflare and similar CDNs must be set to **grey cloud / DNS only**:
  the orange cloud breaks ACME and does not forward QUIC, so the node can never connect
- Opens **TCP 80** automatically for the challenge and closes it right after; renewal is handled by
  `--pre-hook` / `--post-hook` stored in the acme.sh domain config, so no manual work later
- Clients always get `insecure=false`; **no** `allowInsecure` is emitted and `insecure=1` never
  appears in the link
- Produces: Hysteria2 YAML/JSON, sing-box, mihomo, Xray/v2rayN outbound, share link and QR code

Prerequisites: the domain already resolves to this host, and your cloud security group allows
TCP 80 (for issuance and renewal) plus the node's UDP port.

#### 5. Self-signed + SHA-256 certificate pinning (no domain)

- Creates a **private CA** (`CA:TRUE`), then issues a server leaf certificate from it
  (`CA:FALSE`, with `SAN` and `serverAuth`), and computes the leaf's SHA-256 automatically
- Each client gets a path to *real* verification:

  | Client | Verification method |
  |--------|---------------------|
  | **v2rayN (latest, Xray core)** | `pinSHA256` from the link → converted to `pinnedPeerCertSha256`, with `allowInsecure` forced to false |
  | Hysteria2 official / NekoBox | `pinSHA256` in the link and config (colon hex) |
  | mihomo / Clash Meta | `fingerprint` in `clash-meta.yaml` |
  | sing-box | CA certificate embedded in `sing-box.json` |
  | Xray (hand-written config) | `pinnedPeerCertSha256` in `xray-outbound.json` |

- The `insecure=1` in the main link **does not mean "no verification"**: the Hysteria official
  client does not disable standard chain verification when `pinSHA256` is set (Go verifies the
  chain first and only then calls `VerifyPeerCertificate`), so a private CA always fails at that
  first step. Skipping the public CA trust chain is therefore required, and the real check is done
  by the fingerprint. Swap the certificate in a man-in-the-middle and the fingerprint no longer
  matches, so the connection still fails.
- Compatibility artifacts live in separate files (named `*-compat.*`) and carry only `insecure=1`
  with no fingerprint — that really is *no* verification, and it exists solely for old clients
  that don't understand `pinSHA256`. **The latest v2rayN / Xray rejects the compatibility link**
  (`allowInsecure` was removed and the core errors out).
- Stealth note: a self-signed certificate can still be identified by active probing. For the
  strongest resistance to detection, use **option 4**.

> The latest Xray-core supports Hysteria2 natively (`protocol: hysteria` + `network: hysteria` +
> `hysteriaSettings`), and the latest v2rayN runs hy2 nodes on the Xray core. That is why
> `xray-outbound.json` is a complete outbound you can drop straight into `outbounds`.
> The pinning field is named `pinnedPeerCertSha256` (URI shorthand `pcs`) and its value is a
> **colon-separated hex** fingerprint, not base64.

### Firewall policy

After an install or a port change, the script **auto-detects** the local firewall and opens the
hy2 UDP port:

| Detected | Command used |
|----------|--------------|
| ufw is active | `ufw allow <port>/udp` |
| firewalld is running | `firewall-cmd --permanent --add-port=.../udp` |
| Otherwise, iptables present | `iptables -I INPUT -p udp --dport ... -j ACCEPT` (and tries to persist) |
| Nothing found | Only prints a reminder to open it in the cloud security group |

ACME issuance additionally opens **TCP 80 temporarily** using the same logic and closes it as soon
as issuance finishes (success or failure); if 80 was already open beforehand it is left untouched.
Renewal needs port 80 again through acme.sh standalone, so the open/close pair is stored as
`--pre-hook` / `--post-hook` in the domain config and acme.sh toggles it during renewal —
**so it is normal not to see port 80 open in your firewall day to day**.

**Cloud security groups** still have to be opened in the provider's web console; the script cannot
do that for you.

## Supported systems

- Debian / Ubuntu
- CentOS / RHEL / Rocky / Alma / Fedora / Amazon Linux
- Arch (basic support)

Requires **root** and **systemd**.

## Paths after install

| Path | Description |
|------|-------------|
| `/usr/local/bin/hysteria` | Main binary |
| `/etc/hysteria/config.yaml` | Server config (`600`, contains the plaintext password) |
| `/etc/hysteria/install.meta` | Install metadata (`600`, contains the plaintext password) |
| `/etc/hysteria/cert.crt` / `private.key` | Self-signed certificate (default) |
| `/etc/hysteria/ca.crt` / `ca.key` | Private CA (option 5 only; `ca.key` is `600`) |
| `/root/hy/` | Client directory (`700`; every file containing a password is `600`) |
| `/root/hy/hy-client.yaml` / `.json` | Hysteria official client config |
| `/root/hy/clash-meta.yaml` | Clash Meta / mihomo snippet |
| `/root/hy/sing-box.json` | sing-box outbound snippet |
| `/root/hy/url.txt` / `url-qr.png` | Share link and QR code |
| `/root/hy/xray-outbound.json` | Hysteria2 outbound for Xray / v2rayN (options 4 / 5 only) |
| `/root/hy/ca.crt` | Private CA certificate for clients to import (option 5 only) |
| `/root/hy/*-compat.*` / `url-compat.txt` | Compatibility artifacts, `insecure=1`, old clients only (option 5 only) |
| `systemctl status hysteria-server` | Service status |

## Firewall / security group

Open the server's **UDP main port**. With port hopping enabled, also open the corresponding
**UDP port range**.

When using ACME, **TCP 80** must be reachable during issuance (the script opens it and closes it
afterwards; renewal toggles it through acme.sh hooks — see "Firewall policy" above).

## Command-line shortcuts

```bash
bash install-hy2.sh                 # main menu: interactive / one-key
bash install-hy2.sh interactive     # go straight to interactive install
bash install-hy2.sh onekey          # go straight to one-key install
bash install-hy2.sh manage          # management menu
bash install-hy2.sh update          # update Hysteria
bash install-hy2.sh udp             # UDP buffer tuning
bash install-hy2.sh uninstall       # uninstall
bash install-hy2.sh show            # show config
bash install-hy2.sh link            # show share link / QR
bash install-hy2.sh check           # connectivity self-check
bash install-hy2.sh repair          # fix permissions and start
```

**`show` / `link` / `check` / `repair` need no interactive terminal**, so they work under cron or
with output redirected to a log:

```bash
# record a self-check once a day (this path is created by the "update this script" menu item;
# a local file path works just as well)
0 4 * * * /usr/local/bin/install-hy2 check >> /var/log/hy2-check.log 2>&1
```

The other subcommands read input and fail loudly when no TTY is available.

### UDP tuning

Applying it writes `/etc/sysctl.d/99-hysteria2.conf`, mainly raising:

- `net.core.rmem_max` / `wmem_max` (32 MB)
- `net.core.rmem_default` / `wmem_default` (16 MB)
- `net.core.netdev_max_backlog`
- `net.ipv4.udp_rmem_min` / `udp_wmem_min`

You can view, apply or remove that file from the menu at any time.

### Bandwidth / acceleration (Brutal)

**Optional, never asked during install, BBR by default.** Enable it from
"Management → Change config → 5" when you need it.

| Mode | Trigger | Behaviour | Good for |
|------|---------|-----------|----------|
| **BBR** | No bandwidth set (default) | Adaptive probing, backs off on loss | Good lines, low loss |
| **Brutal** | Up/down bandwidth set | Sends at a fixed rate, ignores loss | High-loss cross-border links, jittery latency |

Enabling it writes both the server `config.yaml` and every client config (including the
`upmbps` / `downmbps` parameters in the share link) — **no manual file editing** — and later port
or password changes will not lose the setting.

Tuning notes:

- Use your **real local bandwidth** minus 10–20%; e.g. a measured 100 Mbps downlink → `80`
- **Setting it too high causes self-inflicted loss** and is worse than leaving it off;
  **setting it too low stalls the send window** and causes handshake timeouts
- Judge by **connection success rate first, latency numbers second** — a config with frequent
  timeouts is bad no matter how good the latency looks
- Leave it empty to turn Brutal off and fall back to BBR

> Brutal only flattens jitter and reduces queuing delay; it **cannot reduce physical latency**.
> Base RTT is set by where the server is, so a cross-continent line only truly gets faster by
> moving to a closer region.

### Connectivity self-check

**Runs automatically after install**, and can be triggered any time via "Management → 5" or
`bash install-hy2.sh check`. It is read-only and changes nothing.

Checks performed:

| Check | Description |
|-------|-------------|
| Port the service actually listens on | Compared against the config, catching "the firewall opened a different port" |
| Local firewall | Whether ufw / firewalld / iptables already allows that UDP port |
| Whether the NIC address is private | `10.x` / `172.16-31.x` / `192.168.x` / CGNAT `100.64/10` |
| Egress address | Compared against the NIC address to detect NAT |
| Inbound public IP from cloud metadata | Azure / AWS / GCP / Alibaba Cloud / Tencent Cloud |
| Server-side self-test | Runs a client over loopback to separate "server problem" from "network problem" |

**The most valuable one is the inbound public IP check** — on a host that only has outbound SNAT
and no inbound public address, the script used to happily produce a link that **looked fine but
could never connect**; now it reports FAIL and explains why.

> Cloud security groups (Azure NSG, Alibaba Cloud security groups, etc.) need API credentials, so
> the script cannot touch them; the self-check ends with a reminder to open them in the console.

## Share link examples

```text
hysteria2://PASSWORD@SERVER_IP:PORT/?insecure=1&sni=www.bing.com#Hysteria2
```

- Self-signed defaults to `insecure=1`
- A real ACME certificate defaults to `insecure=0`
- Port hopping appends `mport=first-last`
- Brutal appends `upmbps=10&downmbps=30` (understood by most clients)

With certificate pinning (option 5) the main link looks like:

```text
hysteria2://PASSWORD@SERVER_IP:PORT/?insecure=1&sni=www.bing.com&pinSHA256=5B:02:...:D6#Hysteria2
```

- The `insecure=1` here only skips the public CA trust chain; `pinSHA256` is the real verification
- The latest v2rayN sees `pinSHA256` and forces `allowInsecure=false`, overriding the `insecure=1`
  from the link
- `url-compat.txt` next to it carries only `insecure=1` with no fingerprint — that really is no
  verification, **use it only when an old client does not understand `pinSHA256`**

## Security notes

- Every file containing a plaintext password (`config.yaml`, `install.meta`, `/root/hy/*`) is
  `600` and directories are `700`, so **other local users on the same host cannot read the node
  password**
- When the service runs as `User=hysteria`, the config is `chown`ed to that user and `600` is
  still readable; in extreme cases it degrades to `640 (root:hysteria)` and **never to a
  world-readable 644**
- Passwords are restricted to `A-Za-z0-9._~-`: unambiguous in both YAML and URLs, avoiding a
  `: ` breaking the config or a `*` being parsed as a YAML alias
- Temporary download files always use random `mktemp` names, so a symlink planted in `/tmp`
  cannot hijack them
- The option 5 private CA key `/etc/hysteria/ca.key` is pinned to `root:root 600` and **is not
  handed to the service user by `chown -R`** — whoever holds it can mint any certificate your
  clients will trust, while hysteria itself only needs the leaf certificate and leaf key

## Development / tests

```bash
bash tests/run.sh
```

Pure stubbed tests that **never touch the system** (firewall commands, `curl`, file writes and all
business entry points are stubbed). They run anywhere and need no root. Coverage:

| File | Covers |
|------|--------|
| `tests/test-firewall-tcp.sh` | Borrowing TCP 80 for ACME (ufw / firewalld / iptables / no firewall) |
| `tests/test-update-script.sh` | Self-update download validation: CDN error pages, truncated transfers and empty files are all rejected |
| `tests/test-cli-tty.sh` | TTY gating per subcommand: read-only allowed, interactive blocked |
| `tests/test-cert-pinning.sh` | Certificate options 4 / 5: CA and leaf extensions, fingerprints, per-client artifacts, compatibility artifacts, and options 1–3 regression |

`tests/run.sh` first runs a `bash -n` syntax check, then every `tests/test-*.sh` in turn.

## Notes

- The binary comes from the official Hysteria installer `https://get.hy2.sh/`; no third-party repackaging.
- The bare self-signed certificate in option 1 is only for a quick deploy (the client verifies
  nothing). Use option 5 when you have no domain but want real verification, and option 4 whenever
  you do have a domain.
- ACME renewal is driven by acme.sh's own cron. The script passes `chown` / `chmod` in
  `--reloadcmd` so that renewal does not leave the certificate owned by root and break startup.
- Uninstalling does not remove `acme.sh` or certificates used by other sites on the host; it only
  cleans up what this script created.

## License

MIT
