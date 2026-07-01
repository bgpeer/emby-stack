# media-stack

一键部署自建媒体服务器全家桶,单一导航入口,交互式安装,适合自用或分享给别人。

**Emby** · **qBittorrent** · **Sonarr** · **Radarr** · **Prowlarr** · **Bazarr** · **Jellyseerr**
\+ **Homepage** 导航面板(一个入口点进全部)
\+ 可选 **Caddy** 域名反代 / 自动 HTTPS

---

## 特性

- **交互式安装** —— 跑起来问几个问题(安装目录 / 媒体目录 / 时区 / 权限 / 域名 / 组件多选),不用改代码。
- **单一入口** —— Homepage 面板把所有服务排成卡片,点一下跳转,不用记一堆 `IP:端口`。
- **自动密码** —— qBittorrent 自动注入随机密码;结束打印一张总览表(地址 / 账号 / 密码 / 硬盘),并存到 `CREDENTIALS.txt`。
- **可选域名反代** —— 填域名即自动配子域名 + Let's Encrypt 证书;此模式下服务端口只绑 `127.0.0.1`,不裸奔公网。
- **按需选装** —— 组件可单独开关,只装你要的。
- **幂等** —— 重复运行安全,配置存在 `.env`,随时改了重跑生效。

---

## 快速开始

```bash
curl -fsSL https://raw.githubusercontent.com/bgpeer/emby-stack/main/deploy.sh -o deploy.sh && sudo bash deploy.sh
```

跟着提示回答问题即可。装好后打开导航入口:

- 域名模式:`https://home.你的域名`
- IP 模式:`http://你的IP:3000`

---

## 环境要求

- Linux(Debian/Ubuntu 系测试最充分),root 权限
- Docker + docker compose 插件(脚本可自动安装 Docker)
- 域名反代模式额外需要:一个你拥有的域名,且各子域名(或泛解析 `*.域名`)的 A 记录指向本机公网 IP,放行 80/443

---

## 端口一览

| 服务 | 端口 | 子域名(反代模式) |
|---|---|---|
| Homepage 导航 | 3000 | home |
| Emby | 8096 | emby |
| qBittorrent | 8080 | qb |
| Sonarr | 8989 | sonarr |
| Radarr | 7878 | radarr |
| Prowlarr | 9696 | prowlarr |
| Bazarr | 6767 | bazarr |
| Jellyseerr | 5055 | request |

> qBittorrent 另用 6881(TCP/UDP)做 BT 通信,需放行。

---

## 部署后的一次性对接

容器起来只是搭好架子,让它自动下片入库还需在各网页点几步(脚本无法代劳):

1. **Prowlarr** 添加索引器(你的 BT/PT 站点)→ Add App 连 Sonarr / Radarr。
2. **Sonarr / Radarr** → Settings → Download Clients 添加 qBittorrent(主机填 `qbittorrent`,端口 `8080`,账号密码见 `CREDENTIALS.txt`)。
3. **媒体库路径**:剧集 `/data/tv`,电影 `/data/movies`,下载目录 `/data/downloads`。
   > 所有容器共用同一 `/data`,下载完成到入库是同盘硬链接,不额外占空间。
4. **Emby** 添加媒体库,路径指向 `/data/movies`、`/data/tv`。
5. **Jellyseerr** 首次登录用 Emby 账号,再连 Sonarr / Radarr,做「想看什么点一下自动下」的点播墙。

---

## 常用命令

```bash
cd <安装目录>              # 默认 /opt/media-stack
docker compose ps          # 看状态
docker compose logs -f emby # 看某服务日志
docker compose pull && docker compose up -d   # 升级到最新镜像
docker compose down        # 停止全部
```

卸载:

```bash
sudo bash uninstall.sh
```

---

## 目录结构

```
<安装目录>/
├── docker-compose.yml     # 自动生成
├── .env                   # 你的配置(PUID/TZ/域名等)
├── CREDENTIALS.txt        # 账号密码存档(chmod 600)
├── caddy/Caddyfile        # 反代配置(仅域名模式)
├── emby/config/           # 各服务配置
├── qbittorrent/config/
├── ...
└── media/                 # 媒体与下载
    ├── movies/
    ├── tv/
    └── downloads/
```

---

## 安全提醒

- **IP 模式端口暴露公网**:任何人扫到都能看到登录页。强烈建议限制防火墙来源 IP,或改用域名反代模式(端口自动收进 `127.0.0.1`,仅 Caddy 对外走 443)。
- qBittorrent WebUI 尤其敏感,务必用强密码(脚本已自动设随机密码)。
- 硬盘小的机器(如小内存/小盘 VPS)不适合长期存媒体;媒体服务器要大盘 + 宽流量。别和你的代理节点混用同一台小机器。

---

## 版权与免责

本项目仅提供部署和管理工具,不含、不提供任何影视资源。索引器 / 站点账号需自备。请遵守所在地区法律,仅作个人自用,勿公开分享受版权保护的内容。

## License

MIT
