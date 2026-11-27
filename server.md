# 服务器规范

## 环境概览

Product 环境由三台机器组成：**edge（前端/网关）**、**app（后端）** 和 **media（LiveClass 业务机）**。
另有一台 **legacy**（旧网关）正在退役，见文末「迁移中的 legacy」。

| | edge（前端/网关） | app（后端） | media（LiveClass 业务机） |
|---|---|---|---|
| SSH | `ssh root@10.0.0.1`（tailscale，22 端口；旧入口 `edge.example.com` 仍可用） | `ssh root@10.0.0.3`（tailscale，22 端口） | `ssh root@203.0.113.18`（**无 tailscale**，公网 22 直连）；内网 `10.1.30.119`（仅 legacy 可达） |
| 主机名 | `edge-1` | `app-1` | `media` |
| 系统 | Ubuntu 26.04 LTS | Linux（定制发行版） | CentOS Stream 9 |
| 职责 | 静态资源托管 + API 反向代理；**例外**：已迁入 `ai-relay` / `audio-app` / `oa` 三个业务进程（见下） | 业务服务 + 数据库 + 缓存 | LiveClass（远程双师 / 投屏 / 会议）业务 + 本机 MySQL / Redis；同时托管 `tutor`、`device_tunnel` 两个库（伴学产品） |
| 部署根目录 | `/data/h5`、`/data/static` | `/data/<app>` | `/data/<app>`、`/opt/<app>`（历史原因混用） |
| 运行用户 | nginx 跑 `www-data`；迁入的业务进程跑 `www` | `www:www` | `app`、`ai-relay`、`tutor`（历史用户，未统一） |
| Python | 系统 3.14 + uv 装的 3.11.13 / 3.12.9（`/opt/uv/python`） | 系统 3.14（跑本项目需用 `/home/www/.local/share/uv/python/cpython-3.12.9-linux-x86_64-gnu`，uv 装的解释器，只引用不修改） | 各应用自带 venv（3.9~3.11） |
| 数据库 / 缓存 | **本机** MySQL 8.4（`127.0.0.1:3306`）+ Redis 8（`127.0.0.1:6379`），因业务例外迁入 | 本机 MySQL（数据目录 `/data/mysql`）、Redis | 本机 MySQL 8.0（`127.0.0.1:3306`）、Redis（`127.0.0.1:6379`） |
| 磁盘 | 79G | — | **20G，已用 76%（约剩 4.6G）** —— 有 `relay-retention.timer` 每小时清录课，不要再往上堆数据 |

### 域名与流量路径

| 域名 | 指向 |
|---|---|
| `edge.example.com` | edge |
| `api.example.com` | edge 转发到 app |
| `h5.example.com` | edge |
| `origin.example.com` | app（跨机回源专用，不直接对外提供服务） |
| `live.example.com`、`live-api.example.com` | 目前 DNS 指 legacy，**legacy 只做 TLS 终结，业务全在 media** |
| `media-origin.example.com` | 云厂商 SLB（`203.0.113.212`）终结 TLS，明文回源 **media** 的 `:80` |

```
浏览器
  └─> edge nginx
        ├─ 静态请求（H5 页面、图片、二进制）─> edge 本地文件
        ├─ 已迁入的业务（/ai-relay、/audio-app、/oa）─> edge 本机 127.0.0.1:8000~8002
        └─ API 请求 /<app>/...            ─> https://origin.example.com/<app>/...
                                              └─> app nginx ─> 127.0.0.1:<port>

LiveClass（远程双师 / 投屏 / 会议）
  └─> legacy nginx :443（只做 TLS，`proxy_pass http://10.1.30.119:80`）
        └─> media nginx :80
              ├─ /                                    → screen-relay  8080(WS) / 8081(REST)
              ├─ /meeting*、/api/v1/*、/download、/replay/ → biz-server   8082
              ├─ /meeting-ws、/meeting-asr-ws          → meeting-server 8090
              └─ /livekit/                             → livekit       7880
```

- 所有公网域名都落在 edge，用户请求先到 edge 的 nginx，由它决定「本地出静态文件」还是「转发 app」。
- API 只经 `origin.example.com` 回源到 app，不再有第二条后端路径。

### Tailscale 内网

Tailnet：`ts.example.com`，网段 `10.0.0.0/24`（下表的 `10.0.0.x`）。**日常运维一律走 tailscale IP，不再用公网域名/端口映射。**

| tailscale IP | 节点名 | 实际机器 | 说明 |
|---|---|---|---|
| `10.0.0.1` | `edge` | **edge**（`edge-1`） | 已装好 key，root 直登 |
| `10.0.0.3` | `app` | **app**（`app-1`） | 已装好 key，root 直登 |
| `10.0.0.10` | `api` | **legacy**（`203.0.113.246`） | 节点名与用途不符，`api` 就是 legacy |

- **media 和 QA 没装 tailscale**：media 走公网 `203.0.113.18:22`，或从 legacy 跳到 `10.1.30.119`（edge/app 到 media 内网不通）。

#### Product 本地 SSH Config 参考

```ssh-config
Host edge
    HostName 10.0.0.1
    user root
    port 22

Host app
    HostName 10.0.0.3
    user root
    port 22

Host legacy
    HostName 10.0.0.10
    user root
    port 22

Host media
    HostName 203.0.113.18
    user root
    port 22
```

**media 的密码学提示**：连 media 时 sshd 会打印 `connection is not using a post-quantum key exchange algorithm` 的警告（服务端 OpenSSH 较旧），不影响使用。

**media 的 sshd 限流**：密集建连会被拒，表现为 `Connection closed by 203.0.113.18 port 22`（无其他提示）。多条命令之间 `sleep 3~6`，批量操作写成脚本一次跑完，不要在 for 循环里逐条新建连接。

### Git 服务器

地址 `git.example.com`（HTTPS 与 SSH 同主机）。实例部署、版本与备份见下文「Gitea 实例」。

---

## 应用部署规范

### 后端应用（app）

- 以应用名为目录名，统一部署到 `/data/<app>`，属主 `www:www`。
- 代码放在 `/data/<app>/backend`，虚拟环境放在 `/data/<app>/.venv`。
- 使用 **systemd** 管理进程：service name 与应用名一致，`User=www`、`Group=www`、`WorkingDirectory=/data/<app>/backend`。
- 应用**只监听 `127.0.0.1`**，端口从 `8000` 起按应用递增分配，不与已有应用冲突。
- 内部目录结构请参考 [应用目录结构](app.md#应用目录结构)，需注意文件和目录的权限。
- edge / media 上新迁入的应用**同样按这套约定做**；media 上历史目录（`/opt/<app>`、`app`/`ai-relay`/`tutor` 用户）属于遗留，不新增。

### 前端静态资源（edge）

- H5 应用的编译产物：`/data/h5/<app>`。
- 不属于某个具体应用的静态资源（图片、下载文件等）：`/data/static`。
- 公司官网 `www.site.example.com`：`/data/static/www.site.example.com`，发布后需 `chown -R www-data:www-data`。
- 原则上 edge 只跑 nginx 和静态文件；**当前已确认的例外**：`ai-relay`(8000)、`audio-app`(8001)、`oa`(8002) 三个业务进程与它们自己的 MySQL / Redis 已迁入 edge（原因：原先依赖的 legacy 内网从 edge 不可达）。新增业务请优先落 app，落到 edge 需显式确认。

### 路由接入

- app 侧：在 `/usr/local/nginx/conf/conf.d/origin.example.com.conf` 增加 `location /<app>/` → `proxy_pass http://127.0.0.1:<port>/;`（流式/AI 接口单独加精确 location 以关闭缓冲）。
- edge 侧：把 `/<app>/` 或静态路径配好，静态直出，API 转 `https://origin.example.com`。
- media 侧：LiveClass 的入口在 media 的 `:80`（`liveclass-origin80.conf` / `liveclass-media-origin.conf`），新入口优先加在 `liveclass-origin80.conf`；回源方记得带 `X-Forwarded-Proto: https`。
- 改动配置后先 `nginx -t`，再 reload。

---

## 组件配置

### 反向代理（Nginx）

**edge**

- 系统包安装，配置目录 `/etc/nginx/conf.d/`、`/etc/nginx/sites-enabled/`。
- 管理：`systemctl reload nginx`。

**app**

- 源码安装，前缀 `/usr/local/nginx`（**不在 `PATH` 里**）：二进制 `/usr/local/nginx/sbin/nginx`，站点配置 `/usr/local/nginx/conf/conf.d/`。
- 管理：`systemctl reload nginx`。

**media**

- 系统包安装（`/usr/sbin/nginx`，1.20.1），站点配置 `/etc/nginx/conf.d/`，片段在 `/etc/nginx/snippets/`。
- 管理：`systemctl reload nginx`。
- **media 不终结公网 TLS**（唯一例外是 `/etc/nginx/ssl/media-origin.example.com-tmp` 的自签占位）；只监听 `:80` 与内网 `10.1.30.119:8015`/`:8016`。
- 它的 `:80` vhost 有一条守卫：`if ($http_x_forwarded_proto != "https") { return 301 https://$host$request_uri; }`。从其它机器回源时**必须**带 `X-Forwarded-Proto: https`，否则会被 301 回去（SLB 回源时会形成跳转死循环）。

### 数据库（MySQL）

**app 本机**

- 实例地址：`localhost:3306`，数据目录 `/data/mysql`。
- 访问命令：`mysql`。

**media 本机**

- 实例地址：`127.0.0.1:3306`（只监听本机，公网不可达）。
- 当前库：`tutor`、`device_tunnel`（伴学产品）；`ai-relay`、`oa` 两份待清理。
- 从别的机器访问需建 SSH 隧道（示例见「连接远程 MySQL / Redis」）。
- **edge 本机也有一个 MySQL**（8.4，`127.0.0.1:3306`），供迁入 edge 的 `ai-relay` / `oa` 使用。

### 缓存与消息队列（Redis）

- **app**：`localhost:6379`，以容器（redis-stack）运行。
- **media**：`127.0.0.1:6379`，系统包安装。
- **edge**：`127.0.0.1:6379`（系统包），目前只有 `ai-relay` 的限流计数（db5）。
- 访问命令：`redis-cli`。

### media 专属说明（LiveClass 业务机）

| systemd 单元 | 端口 | 作用 |
|---|---|---|
| `biz-server` | `127.0.0.1:8082` | LiveClass 管理后台 / 业务 API（FastAPI + **SQLite**），建房、入室校验、在线统计、「课时与费用」计费 |
| `screen-relay-server` | `127.0.0.1:8080`(WS) / `8081`(REST) | 投屏转发、鉴权、录制上传与回放，按 `Upgrade` 头分流 |
| `meeting-server` | `127.0.0.1:8090` / `8091` | 自研会议媒体服务（WS 音视频） |
| `liveclass-livekit` | `*:7880` / `*:7881` | LiveKit SFU（信令 + WebRTC），**监听 0.0.0.0，需靠安全组控制** |
| `liveclass-monitor.timer` | — | 每分钟一次系统监控 |
| `relay-retention.timer` | — | 每小时清理录课（只保留最近 5 个房间） |
| `ai-relay` / `audio-app` / `oa` | `0.0.0.0:8020` / `127.0.0.1:8013` / `127.0.0.1:8014` | **已迁到 edge，这里是并行副本**，切流完成后 stop + disable |

其它约定：

- **磁盘只有 20G**（现用 76%）：`/data/liveclass`（录课 + 发布件）2.0G、`/data/oa` 1.7G。历史上两次被录课文件顶到 99% 把 `biz-server` 打挂（`database or disk is full`），才加的 `relay-retention`。往 media 加数据前先看 `df -h`。
- 录课发布件已迁到对象存储（S3 兼容，`release.example.com`），`/release/*` 只做 302，不要再传回本地。
- 历史部署目录混用 `/opt/<app>`（biz-server、audio-app、screen-relay-server、device-tunnel）与 `/data/<app>`（liveclass、oa、ai-relay），用户也不统一；**新迁入的服务请按上面的 `/data/<app>` + `www:www` + systemd 约定做**。
- 伴学产品的 `tutor` + `device-api` 目前仍跑在 legacy，通过 `legacy-mysql-tunnel.service`（`127.0.0.1:3307 → media:3306`）连 media 的库；迁移目标为 **edge**：两个业务进程与 media 上的 `tutor`、`device_tunnel` 两个 MySQL 库同批迁入 edge，切流后这条隧道即可退役。

### WSGI / ASGI 服务

- 使用 **gunicorn** 作为 WSGI 服务器。
- 对于 FastAPI 应用，使用 **uvicorn** 异步 worker 运行。

---

## H5 应用规范

- 编译产物部署到 **edge** 的 `/data/h5/<app>`，由 edge 的 nginx 直接静态托管。
- 访问地址：
  - Product：`https://h5.example.com/<app>`
  - QA：`https://h5.qa.example.com/<app>`
- H5 域名只做静态托管，登录态 cookie 由后端在 API 域名下发（见 [app.md](app.md#多应用共用域名的登录态隔离)）。

---

## QA 环境

QA 是独立于 edge / app / media 的单机，不与 Product 共享任何目录或服务。

- SSH / 入口：`qa.example.com`（**无 tailscale**，只能走域名/公网）；API / 健康检查通过 `api.qa.example.com`。
- 系统：Debian 12，nginx 1.22，Python 3.11。
- 应用部署在 `/opt/<app>`，以 `app` 用户启动，systemd 管理方式与 Product 一致。

---

## Gitea 实例（`git.example.com`）

edge 上的二进制 + systemd 部署：`/usr/local/bin/gitea`、`gitea.service`、配置 `/etc/gitea/app.ini`、数据 `/var/lib/gitea`；nginx 反代 `127.0.0.1:3000`（带 WebSocket Upgrade 头）。

| 项 | 值 |
|---|---|
| 版本 | 28.4.0 |
| 数据库 | SQLite `/var/lib/gitea/data/gitea.db` |
| 仓库 / 用户 / action run | 73 / 15 / ~700 |
| `gitea` 子命令 | 必须以 `git` 用户运行，root 会被拒绝 |
| `gitea dump` | 不能加 `--skip-repository`：仓库目录在 APP_DATA_PATH 之内，加了会丢全部仓库 |
| 备份 | `/root/gitea-backup-20261117-193557/`：`gitea-dump-1.25.3-full.zip`、`var-lib-gitea.tar.gz`、`gitea.db-1.25.3.snapshot`、旧二进制 `gitea-1.25.3`；sha256 清单 `/root/gitea-backup-SHA256.txt` |

---

## CI Runner（Gitea Actions）

runner 在**开发机 Mac 的 Docker 里**（colima 虚拟机：4 核 / 8G / 60G）。

| 项 | 值 |
|---|---|
| 注册名 / Gitea runner id | `mac-ci` / 5 |
| 版本 | gitea/runner v6.0.0（二进制 `gitea-runner`） |
| label | `ubuntu-latest:docker://ci-runner:20.20.2-v6`（每个 job 一个一次性容器） |
| 定义与部署 | `~/ci-runner`：`Dockerfile` + `docker-compose.yml` + `data/config.yaml`（capacity 2） |
| 镜像 | `ci-runner:20.20.2-v6`：ubuntu 24.04 + node 20.20.2 + python3 + build-essential，runner 容器与 job 容器共用 |
| 存储 | 注册凭证与配置在命名卷 `ci-runner_ci-data`，挂到 `/opt/runner` |
| action 源 | runner `github_mirror: https://gitea.com`；Gitea `DEFAULT_ACTIONS_URL = github`（`/etc/gitea/app.ini`） |
| 宿主挂载 | colima `--mount none`；容器只挂 `/var/run/docker.sock` 和命名卷 |
| 启停 / 日志 | 该目录下 `docker compose up -d` / `docker compose logs -f` |
| 开机自启 | `brew services start colima`（已设）；容器 `restart: unless-stopped` |

- job 容器由 colima 的 dockerd 创建，与 runner 容器同级（DooD）；`container.docker_host: "-"` + `container.valid_volumes: []` 保证 job 读不到 `/opt/runner/.runner`、Mac 目录和 docker socket。
- **Mac 休眠/关机时 CI 不会跑**，Gitea 里该 runner 显示离线。
- edge 上 `gitea-runner.service` 为 `disabled` / `inactive`，二进制在 `/opt/act_runner`。
- **Gitea 的 `schedule` cron 按 UTC 解析**（与服务器/容器时区无关）：要本地 03:00 跑就写 `0 19 * * *`。

---

## 迁移中的 legacy（旧网关，待退役）

`legacy`（公网 `203.0.113.246`、内网 `10.1.30.116`、tailscale `10.0.0.10`（节点名 `api`），Debian 12 + nginx 1.22.1）是迁移前的公网入口，
现在仍在做部分域名的 TLS 终结与分流，全部迁完后退役。

- **仍在 legacy 上的业务进程**：`core-api`(8000，兼当 `api.example.com/` 的兜底)、伴学产品的 `tutor`(8010) 与 `device-api`(9765/9766)、`coturn`(3478，已基本无流量)、`metrics-agent` / `monitor-agent`(监控)
- **仍在 legacy 上做 TLS 入口的域名**：`live` / `live-api`（业务在 media）、`media-origin`（真入口是云厂商 SLB，legacy 只有自签占位）、`core-api`、`www` / `api` / `h5`.site.example.com、`portal.example.com`（已无 DNS）、`app.example.com`、`admin.example.com`（已无 DNS）
- `www.site.example.com`（纯静态官网）的 vhost 与文件已在 edge 备好：`/etc/nginx/conf.d/www.site.example.com.conf`、`/data/static/www.site.example.com`；DNS 仍指 legacy，切流与验收见 edge 上 `/root/edge-migrate/README-www-site.md`
- `api` / `portal`.site.example.com 与 `h5`.site.example.com 不单独迁：前两者的后端就是 legacy 的 `core-api`（真实流量为零，日志里只有扫描器），随 `core-api` 一起处理；`h5` 是 2024-12 构建、已无维护的早期静态包
- legacy 的 MySQL（`127.0.0.1:3306`）仍有 `core-api` 等库；Redis 本机
- 详细清单、依赖与批次见 edge 上 `/root/edge-migrate/README-*.md`
- **legacy 上不要再新增任何东西**；修改配置前先备份到 `/root/edge-migrate/orig/`

---

## 开发环境配置

开发环境已配置好 QA 服务器的 SSH key，可随时通过 SSH 连接服务器（可先用 `root` 用户尝试）。

### Product 服务器直连检查

edge / app 走 tailscale 内网，**开发机必须先装并登录 tailscale**（tailnet `ts.example.com`），否则 `10.0.0.x` 全部连不上。media 走公网。在执行任何涉及 product 的操作前，先运行：

```bash
ssh root@10.0.0.1 'echo ok'            # edge（tailscale）
ssh root@10.0.0.3 'echo ok'            # app（tailscale）
ssh root@203.0.113.18 'echo ok'          # media（公网直连，22 端口）
```

- 若返回 `ok`，说明已授权直连，可继续操作。
- 若连接被拒绝或超时，先确认 tailscale 是否已登录且在线，再向用户确认访问方式（如跳板机、临时授权等）。

### 本地开发环境

开发环境只需配置反向代理、hosts 绑定和本地应用，**不需要**配置 MySQL 和 Redis。

#### 连接远程 MySQL / Redis

**app 的 MySQL / Redis 在 tailnet 内是直通的**（`*:3306` / `*:6379`），本地直接填 `10.0.0.3`，不需要隧道。其余走 SSH 隧道：

```bash
ssh root@10.0.0.1 -L 3306:localhost:3306   # edge 的 MySQL（只绑 127.0.0.1）
ssh root@10.0.0.1 -L 6379:localhost:6379   # edge 的 Redis
ssh root@203.0.113.18 -L 3307:localhost:3306 # media 的 MySQL（无 tailscale，只能隧道）
ssh root@10.0.0.10 -L 3308:localhost:3306  # legacy 的 MySQL（也可直接连 10.0.0.10:3306）
```

使用 `config.toml` 中的配置连接本地对应端口。

### 访问服务器资源

本地已配置好 SSH key。若需修改服务器配置，使用 `ssh` 连接服务器后在服务器上执行相应命令（具体命令参见“组件配置”章节）。
