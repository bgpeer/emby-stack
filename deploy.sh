#!/usr/bin/env bash
# =============================================================================
#  media-stack :: 一键自建媒体服务器全家桶
#  Emby + qBittorrent + Sonarr + Radarr + Prowlarr + Bazarr + Jellyseerr
#  + Homepage 导航面板(单一入口)  + 可选 Caddy 域名反代 / 自动 HTTPS
#
#  特性:
#   - 交互式问答:安装目录 / 媒体目录 / 时区 / PUID-PGID / 域名 / 组件多选
#   - 自动生成随机密码(qBittorrent 直接注入,免手动)
#   - 单一导航入口(Homepage),点击卡片跳转各服务
#   - 可选域名反代:填域名即自动配子域名 + Let's Encrypt HTTPS
#   - 幂等:重复运行安全,配置写入 .env,可随时改
#   - 结束打印总览表(地址 / 账号 / 密码 / 硬盘空间),并存档到 CREDENTIALS.txt
#
#  用法:  sudo bash deploy.sh
#  卸载:  sudo bash uninstall.sh
# =============================================================================
set -euo pipefail

# ---------- 颜色 ----------
c_reset=$'\e[0m'; c_bold=$'\e[1m'; c_dim=$'\e[2m'
c_green=$'\e[32m'; c_yellow=$'\e[33m'; c_red=$'\e[31m'; c_cyan=$'\e[36m'; c_blue=$'\e[34m'
info(){ printf '%s\n' "${c_cyan}>>>${c_reset} $*"; }
ok(){   printf '%s\n' "${c_green}✔${c_reset} $*"; }
warn(){ printf '%s\n' "${c_yellow}⚠${c_reset} $*"; }
err(){  printf '%s\n' "${c_red}✗${c_reset} $*" >&2; }
hr(){   printf '%s\n' "${c_dim}────────────────────────────────────────────────────────${c_reset}"; }

# ---------- 前置检查 ----------
require_root(){
  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    err "请用 root 运行:sudo bash deploy.sh"; exit 1
  fi
}

ensure_docker(){
  if command -v docker >/dev/null 2>&1; then
    ok "Docker 已安装:$(docker --version | awk '{print $3}' | tr -d ,)"
  else
    warn "未检测到 Docker。"
    read -rp "$(printf '是否自动安装 Docker? [Y/n] ')" a; a=${a:-Y}
    if [[ "$a" =~ ^[Yy]$ ]]; then
      info "正在安装 Docker(官方脚本)..."
      curl -fsSL https://get.docker.com | sh
      systemctl enable --now docker
      ok "Docker 安装完成"
    else
      err "需要 Docker 才能继续。"; exit 1
    fi
  fi
  if docker compose version >/dev/null 2>&1; then
    ok "docker compose 可用"
  else
    err "缺少 docker compose 插件。请升级 Docker 或安装 compose 插件后重试。"; exit 1
  fi
}

# ---------- 生成随机密码(子 shell 隔离 pipefail,避免 head 关闭管道时 tr 收到 SIGPIPE 终止脚本) ----------
rand_pw(){ ( set +o pipefail; LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c "${1:-16}" ); }

# ---------- 询问工具 ----------
ask(){ # ask VAR "提示" "默认值"
  local __var="$1" __prompt="$2" __default="${3:-}" __ans
  if [[ -n "$__default" ]]; then
    read -rp "$(printf '%s [%s]: ' "$__prompt" "$__default")" __ans
    __ans=${__ans:-$__default}
  else
    read -rp "$(printf '%s: ' "$__prompt")" __ans
  fi
  printf -v "$__var" '%s' "$__ans"
}
ask_yn(){ # ask_yn VAR "提示" "Y|N"
  local __var="$1" __prompt="$2" __default="${3:-N}" __ans
  read -rp "$(printf '%s [%s]: ' "$__prompt" "$( [[ $__default == Y ]] && echo 'Y/n' || echo 'y/N')")" __ans
  __ans=${__ans:-$__default}
  [[ "$__ans" =~ ^[Yy]$ ]] && printf -v "$__var" 'yes' || printf -v "$__var" 'no'
}
ask_service(){ # ask_service VAR "名称" 默认yes
  local __var="$1" __name="$2" __default="${3:-Y}" __ans
  read -rp "$(printf '  安装 %-28s [%s]: ' "$__name" "$( [[ $__default == Y ]] && echo 'Y/n' || echo 'y/N')")" __ans
  __ans=${__ans:-$__default}
  [[ "$__ans" =~ ^[Yy]$ ]] && printf -v "$__var" 'yes' || printf -v "$__var" 'no'
}

# =============================================================================
#  开始
# =============================================================================
require_root
clear
cat <<'BANNER'
  ┌─────────────────────────────────────────────────────────┐
  │   media-stack  ·  自建媒体服务器一键部署                 │
  │   Emby / qB / Sonarr / Radarr / Prowlarr / Bazarr /      │
  │   Jellyseerr  +  Homepage 导航  +  可选域名反代          │
  └─────────────────────────────────────────────────────────┘
BANNER
echo
ensure_docker
hr

# ---------- 交互式问答 ----------
info "接下来问你几个问题,直接回车用默认值。"
echo
ask INSTALL_DIR "安装目录(存放配置)"        "/opt/media-stack"
ask MEDIA_DIR   "媒体目录(存放影视文件)"    "${INSTALL_DIR}/media"
ask TZ_VAL      "时区"                          "Asia/Shanghai"
echo
warn "PUID/PGID 决定容器内进程的文件权限。个人 VPS 用 0 最省事;"
warn "多用户或安全要求高,建议用普通用户(先 id yourname 查)。"
ask PUID "PUID" "0"
ask PGID "PGID" "0"
echo
hr
info "选择要安装的服务(多选,回车=装):"
ask_service S_EMBY       "Emby(媒体播放)"          Y
ask_service S_QBIT       "qBittorrent(下载)"        Y
ask_service S_SONARR     "Sonarr(剧集自动化)"       Y
ask_service S_RADARR     "Radarr(电影自动化)"       Y
ask_service S_PROWLARR   "Prowlarr(索引器)"         Y
ask_service S_BAZARR     "Bazarr(字幕)"             Y
ask_service S_JELLYSEERR "Jellyseerr(点播墙)"       Y
ask_service S_HOMEPAGE   "Homepage(导航入口·推荐)"  Y
hr

# ---------- 域名反代 ----------
DOMAIN=""; ACME_EMAIL=""; USE_PROXY="no"
info "入口方式:"
echo "  · 不填域名 → 直接用 IP:端口 访问(简单,但端口裸奔公网,注意防火墙)"
echo "  · 填域名   → 自动配 Caddy 反代 + HTTPS,子域名统一入口(推荐)"
echo
ask_yn USE_PROXY "是否启用域名反代(需要一个你拥有的域名)?" N
if [[ "$USE_PROXY" == "yes" ]]; then
  ask DOMAIN     "主域名(如 media.example.com,各服务会用它的子域名)" ""
  ask ACME_EMAIL "Let's Encrypt 邮箱(证书到期提醒用)" ""
  if [[ -z "$DOMAIN" ]]; then
    warn "未填域名,自动改回 IP:端口 模式。"; USE_PROXY="no"
  else
    warn "请确保以下子域名的 DNS A 记录都已指向本机公网 IP:"
    for sub in home emby qb sonarr radarr prowlarr bazarr request; do
      echo "     ${sub}.${DOMAIN}"
    done
    echo "  (或直接加一条泛解析 *.${DOMAIN} A 记录,最省事)"
    read -rp "  DNS 配好了?回车继续,Ctrl-C 退出去配 DNS... " _
  fi
fi
hr

# ---------- 派生变量 ----------
HOST_IP="$(curl -fsS4 --max-time 5 https://api.ipify.org 2>/dev/null || hostname -I | awk '{print $1}')"
COMPOSE_FILE="${INSTALL_DIR}/docker-compose.yml"
ENV_FILE="${INSTALL_DIR}/.env"
CRED_FILE="${INSTALL_DIR}/CREDENTIALS.txt"
NET_NAME="mediastack"

# 数据目录:所有服务共用同一 /data,便于下载→入库硬链接,避免复制
DATA_ROOT="${MEDIA_DIR}"

QBIT_USER="admin"
QBIT_PASS="$(rand_pw 16)"

info "创建目录结构..."
mkdir -p "$INSTALL_DIR"
mkdir -p "$DATA_ROOT"/{movies,tv,downloads}
for svc in emby qbittorrent sonarr radarr prowlarr bazarr jellyseerr homepage caddy; do
  mkdir -p "${INSTALL_DIR}/${svc}/config"
done
ok "目录就绪:配置在 ${INSTALL_DIR}/<服务>/config,媒体在 ${DATA_ROOT}"

# ---------- 写 .env ----------
cat > "$ENV_FILE" <<EOF
# media-stack 环境变量(可修改后重跑 deploy.sh 生效)
PUID=${PUID}
PGID=${PGID}
TZ=${TZ_VAL}
INSTALL_DIR=${INSTALL_DIR}
DATA_ROOT=${DATA_ROOT}
DOMAIN=${DOMAIN}
ACME_EMAIL=${ACME_EMAIL}
USE_PROXY=${USE_PROXY}
EOF
chmod 600 "$ENV_FILE"

# 反代模式下,服务端口只绑定 127.0.0.1(不裸奔公网,仅 Caddy 对外)
if [[ "$USE_PROXY" == "yes" ]]; then BIND="127.0.0.1:"; else BIND=""; fi

# =============================================================================
#  生成 docker-compose.yml
# =============================================================================
info "生成 docker-compose.yml..."
{
echo "# 由 deploy.sh 自动生成。可手动修改后 docker compose up -d 生效。"
echo "name: mediastack"
echo "services:"

# ---- Emby ----
if [[ "$S_EMBY" == "yes" ]]; then cat <<YAML
  emby:
    image: emby/embyserver:latest
    container_name: emby
    restart: unless-stopped
    environment:
      - UID=\${PUID}
      - GID=\${PGID}
      - TZ=\${TZ}
    volumes:
      - \${INSTALL_DIR}/emby/config:/config
      - \${DATA_ROOT}:/data
    ports:
      - "${BIND}8096:8096"
    networks:
      - mediastack
YAML
fi

# ---- qBittorrent ----
if [[ "$S_QBIT" == "yes" ]]; then cat <<YAML
  qbittorrent:
    image: lscr.io/linuxserver/qbittorrent:latest
    container_name: qbittorrent
    restart: unless-stopped
    environment:
      - PUID=\${PUID}
      - PGID=\${PGID}
      - TZ=\${TZ}
      - WEBUI_PORT=8080
    volumes:
      - \${INSTALL_DIR}/qbittorrent/config:/config
      - \${DATA_ROOT}:/data
    ports:
      - "${BIND}8080:8080"
      - "6881:6881"
      - "6881:6881/udp"
    networks:
      - mediastack
YAML
fi

# ---- Prowlarr ----
if [[ "$S_PROWLARR" == "yes" ]]; then cat <<YAML
  prowlarr:
    image: lscr.io/linuxserver/prowlarr:latest
    container_name: prowlarr
    restart: unless-stopped
    environment:
      - PUID=\${PUID}
      - PGID=\${PGID}
      - TZ=\${TZ}
    volumes:
      - \${INSTALL_DIR}/prowlarr/config:/config
    ports:
      - "${BIND}9696:9696"
    networks:
      - mediastack
YAML
fi

# ---- Sonarr ----
if [[ "$S_SONARR" == "yes" ]]; then cat <<YAML
  sonarr:
    image: lscr.io/linuxserver/sonarr:latest
    container_name: sonarr
    restart: unless-stopped
    environment:
      - PUID=\${PUID}
      - PGID=\${PGID}
      - TZ=\${TZ}
    volumes:
      - \${INSTALL_DIR}/sonarr/config:/config
      - \${DATA_ROOT}:/data
    ports:
      - "${BIND}8989:8989"
    networks:
      - mediastack
YAML
fi

# ---- Radarr ----
if [[ "$S_RADARR" == "yes" ]]; then cat <<YAML
  radarr:
    image: lscr.io/linuxserver/radarr:latest
    container_name: radarr
    restart: unless-stopped
    environment:
      - PUID=\${PUID}
      - PGID=\${PGID}
      - TZ=\${TZ}
    volumes:
      - \${INSTALL_DIR}/radarr/config:/config
      - \${DATA_ROOT}:/data
    ports:
      - "${BIND}7878:7878"
    networks:
      - mediastack
YAML
fi

# ---- Bazarr ----
if [[ "$S_BAZARR" == "yes" ]]; then cat <<YAML
  bazarr:
    image: lscr.io/linuxserver/bazarr:latest
    container_name: bazarr
    restart: unless-stopped
    environment:
      - PUID=\${PUID}
      - PGID=\${PGID}
      - TZ=\${TZ}
    volumes:
      - \${INSTALL_DIR}/bazarr/config:/config
      - \${DATA_ROOT}:/data
    ports:
      - "${BIND}6767:6767"
    networks:
      - mediastack
YAML
fi

# ---- Jellyseerr ----
if [[ "$S_JELLYSEERR" == "yes" ]]; then cat <<YAML
  jellyseerr:
    image: fallenbagel/jellyseerr:latest
    container_name: jellyseerr
    restart: unless-stopped
    environment:
      - TZ=\${TZ}
    volumes:
      - \${INSTALL_DIR}/jellyseerr/config:/app/config
    ports:
      - "${BIND}5055:5055"
    networks:
      - mediastack
YAML
fi

# ---- Homepage 导航面板 ----
if [[ "$S_HOMEPAGE" == "yes" ]]; then cat <<YAML
  homepage:
    image: ghcr.io/gethomepage/homepage:latest
    container_name: homepage
    restart: unless-stopped
    environment:
      - PUID=\${PUID}
      - PGID=\${PGID}
      - TZ=\${TZ}
      - HOMEPAGE_ALLOWED_HOSTS=*
    volumes:
      - \${INSTALL_DIR}/homepage/config:/app/config
    ports:
      - "${BIND}3000:3000"
    networks:
      - mediastack
YAML
fi

# ---- Caddy 反代(仅域名模式)----
if [[ "$USE_PROXY" == "yes" ]]; then cat <<YAML
  caddy:
    image: caddy:latest
    container_name: caddy
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - \${INSTALL_DIR}/caddy/Caddyfile:/etc/caddy/Caddyfile:ro
      - \${INSTALL_DIR}/caddy/data:/data
      - \${INSTALL_DIR}/caddy/config:/config
    networks: [ mediastack ]
YAML
fi

echo ""
echo "networks:"
echo "  mediastack:"
echo "    name: mediastack"
} > "$COMPOSE_FILE"
ok "compose 写入 $COMPOSE_FILE"

# =============================================================================
#  生成 Caddyfile(域名模式)
# =============================================================================
if [[ "$USE_PROXY" == "yes" ]]; then
  info "生成 Caddyfile..."
  {
    [[ -n "$ACME_EMAIL" ]] && echo "{ email ${ACME_EMAIL} }" && echo
    [[ "$S_HOMEPAGE"   == yes ]] && echo "home.${DOMAIN}     { reverse_proxy homepage:3000 }"
    [[ "$S_EMBY"       == yes ]] && echo "emby.${DOMAIN}     { reverse_proxy emby:8096 }"
    [[ "$S_QBIT"       == yes ]] && echo "qb.${DOMAIN}       { reverse_proxy qbittorrent:8080 }"
    [[ "$S_SONARR"     == yes ]] && echo "sonarr.${DOMAIN}   { reverse_proxy sonarr:8989 }"
    [[ "$S_RADARR"     == yes ]] && echo "radarr.${DOMAIN}   { reverse_proxy radarr:7878 }"
    [[ "$S_PROWLARR"   == yes ]] && echo "prowlarr.${DOMAIN} { reverse_proxy prowlarr:9696 }"
    [[ "$S_BAZARR"     == yes ]] && echo "bazarr.${DOMAIN}   { reverse_proxy bazarr:6767 }"
    [[ "$S_JELLYSEERR" == yes ]] && echo "request.${DOMAIN}  { reverse_proxy jellyseerr:5055 }"
  } > "${INSTALL_DIR}/caddy/Caddyfile"
  mkdir -p "${INSTALL_DIR}/caddy/data" "${INSTALL_DIR}/caddy/config"
  ok "Caddyfile 写入 ${INSTALL_DIR}/caddy/Caddyfile"
fi

# =============================================================================
#  生成 Homepage 配置(导航入口)
# =============================================================================
if [[ "$S_HOMEPAGE" == "yes" ]]; then
  info "生成 Homepage 导航配置..."
  HP="${INSTALL_DIR}/homepage/config"
  mkdir -p "$HP"

  # 外链地址:域名模式用子域名,否则用 IP:端口
  url_for(){ # url_for 子域名 端口
    if [[ "$USE_PROXY" == "yes" ]]; then echo "https://$1.${DOMAIN}"; else echo "http://${HOST_IP}:$2"; fi
  }

  cat > "${HP}/settings.yaml" <<YAML
title: 我的媒体中心
theme: dark
color: slate
headerStyle: clean
layout:
  媒体:
    style: row
    columns: 3
  下载与自动化:
    style: row
    columns: 3
YAML

  {
    echo "- 媒体:"
    if [[ "$S_EMBY" == yes ]]; then cat <<CARD
    - Emby:
        icon: emby.png
        href: $(url_for emby 8096)
        description: 影视播放
        siteMonitor: http://emby:8096
CARD
    fi
    if [[ "$S_JELLYSEERR" == yes ]]; then cat <<CARD
    - Jellyseerr:
        icon: jellyseerr.png
        href: $(url_for request 5055)
        description: 想看什么点这里
        siteMonitor: http://jellyseerr:5055
CARD
    fi
    echo "- 下载与自动化:"
    if [[ "$S_QBIT" == yes ]]; then cat <<CARD
    - qBittorrent:
        icon: qbittorrent.png
        href: $(url_for qb 8080)
        description: 下载器
        siteMonitor: http://qbittorrent:8080
CARD
    fi
    if [[ "$S_RADARR" == yes ]]; then cat <<CARD
    - Radarr:
        icon: radarr.png
        href: $(url_for radarr 7878)
        description: 电影自动化
        siteMonitor: http://radarr:7878
CARD
    fi
    if [[ "$S_SONARR" == yes ]]; then cat <<CARD
    - Sonarr:
        icon: sonarr.png
        href: $(url_for sonarr 8989)
        description: 剧集自动化
        siteMonitor: http://sonarr:8989
CARD
    fi
    if [[ "$S_PROWLARR" == yes ]]; then cat <<CARD
    - Prowlarr:
        icon: prowlarr.png
        href: $(url_for prowlarr 9696)
        description: 索引器聚合
        siteMonitor: http://prowlarr:9696
CARD
    fi
    if [[ "$S_BAZARR" == yes ]]; then cat <<CARD
    - Bazarr:
        icon: bazarr.png
        href: $(url_for bazarr 6767)
        description: 字幕下载
        siteMonitor: http://bazarr:6767
CARD
    fi
  } > "${HP}/services.yaml"

  cat > "${HP}/widgets.yaml" <<YAML
- resources:
    cpu: true
    memory: true
    disk: /
- search:
    provider: google
    target: _blank
YAML

  : > "${HP}/bookmarks.yaml"
  : > "${HP}/docker.yaml"
  ok "Homepage 配置就绪"
fi

# =============================================================================
#  拉取镜像并启动
# =============================================================================
hr
info "拉取镜像并启动(首次较慢,取决于网络)..."
( cd "$INSTALL_DIR" && docker compose --env-file "$ENV_FILE" up -d )
ok "容器已启动"

# =============================================================================
#  qBittorrent:注入随机密码(免手动)
# =============================================================================
if [[ "$S_QBIT" == "yes" ]]; then
  info "为 qBittorrent 注入随机密码..."
  QCONF_DIR="${INSTALL_DIR}/qbittorrent/config/qBittorrent"
  QCONF="${QCONF_DIR}/qBittorrent.conf"
  # 等待容器首次生成默认配置
  for _ in $(seq 1 20); do [[ -f "$QCONF" ]] && break; sleep 2; done

  if command -v python3 >/dev/null 2>&1 && [[ -f "$QCONF" ]]; then
    docker stop qbittorrent >/dev/null 2>&1 || true
    PBKDF2="$(python3 - "$QBIT_PASS" <<'PY'
import sys, os, hashlib, base64
pw = sys.argv[1].encode()
salt = os.urandom(16)
dk = hashlib.pbkdf2_hmac('sha512', pw, salt, 100000, dklen=64)
print("@ByteArray(%s:%s)" % (base64.b64encode(salt).decode(), base64.b64encode(dk).decode()))
PY
)"
    # 用 python 安全地写入 [Preferences] 段
    REV="$([[ "$USE_PROXY" == yes ]] && echo true || echo false)"
    python3 - "$QCONF" "$QBIT_USER" "$PBKDF2" "$REV" <<'PY'
import sys, configparser
path, user, pbkdf2, rev = sys.argv[1:5]
cp = configparser.RawConfigParser()
cp.optionxform = str            # 保留大小写与反斜杠键名
cp.read(path, encoding='utf-8')
if not cp.has_section('Preferences'):
    cp.add_section('Preferences')
cp.set('Preferences', r'WebUI\Username', user)
cp.set('Preferences', r'WebUI\Password_PBKDF2', '"%s"' % pbkdf2)
if rev == 'true':               # 反代模式:放行 host 头,避免登录报错
    cp.set('Preferences', r'WebUI\HostHeaderValidation', 'false')
    cp.set('Preferences', r'WebUI\CSRFProtection', 'false')
with open(path, 'w', encoding='utf-8') as f:
    cp.write(f, space_around_delimiters=False)
PY
    docker start qbittorrent >/dev/null 2>&1 || true
    ok "qBittorrent 密码已设为随机值(见下方总览)"
  else
    warn "未找到 python3 或配置文件,无法自动设密码。"
    warn "请用日志里的临时密码首登:docker logs qbittorrent | grep -i password"
    QBIT_PASS="(见 docker logs qbittorrent | grep -i password)"
  fi
fi

# =============================================================================
#  总览表
# =============================================================================
DISK_LINE="$(df -h "$INSTALL_DIR" | awk 'NR==2{printf "总 %s / 已用 %s / 可用 %s (%s)", $2,$3,$4,$5}')"

print_row(){ printf "  %-13s %-34s %s\n" "$1" "$2" "$3"; }
sep(){ printf '%s\n' "  ------------------------------------------------------------"; }

gen_summary(){
  echo "服务地址一览(生成时间:$(date '+%F %T'))"
  sep
  printf "  %-13s %-34s %s\n" "服务" "访问地址" "账号/密码"
  sep
  local u
  if [[ "$USE_PROXY" == "yes" ]]; then
    [[ "$S_HOMEPAGE"   == yes ]] && print_row "首页入口"   "https://home.${DOMAIN}"     "—"
    [[ "$S_EMBY"       == yes ]] && print_row "Emby"       "https://emby.${DOMAIN}"     "首登自设"
    [[ "$S_JELLYSEERR" == yes ]] && print_row "Jellyseerr" "https://request.${DOMAIN}"  "首登自设"
    [[ "$S_QBIT"       == yes ]] && print_row "qBittorrent" "https://qb.${DOMAIN}"      "${QBIT_USER} / ${QBIT_PASS}"
    [[ "$S_RADARR"     == yes ]] && print_row "Radarr"     "https://radarr.${DOMAIN}"   "首登自设"
    [[ "$S_SONARR"     == yes ]] && print_row "Sonarr"     "https://sonarr.${DOMAIN}"   "首登自设"
    [[ "$S_PROWLARR"   == yes ]] && print_row "Prowlarr"   "https://prowlarr.${DOMAIN}" "首登自设"
    [[ "$S_BAZARR"     == yes ]] && print_row "Bazarr"     "https://bazarr.${DOMAIN}"   "首登自设"
  else
    [[ "$S_HOMEPAGE"   == yes ]] && print_row "首页入口"   "http://${HOST_IP}:3000"  "—"
    [[ "$S_EMBY"       == yes ]] && print_row "Emby"       "http://${HOST_IP}:8096"  "首登自设"
    [[ "$S_JELLYSEERR" == yes ]] && print_row "Jellyseerr" "http://${HOST_IP}:5055"  "首登自设"
    [[ "$S_QBIT"       == yes ]] && print_row "qBittorrent" "http://${HOST_IP}:8080" "${QBIT_USER} / ${QBIT_PASS}"
    [[ "$S_RADARR"     == yes ]] && print_row "Radarr"     "http://${HOST_IP}:7878"  "首登自设"
    [[ "$S_SONARR"     == yes ]] && print_row "Sonarr"     "http://${HOST_IP}:8989"  "首登自设"
    [[ "$S_PROWLARR"   == yes ]] && print_row "Prowlarr"   "http://${HOST_IP}:9696"  "首登自设"
    [[ "$S_BAZARR"     == yes ]] && print_row "Bazarr"     "http://${HOST_IP}:6767"  "首登自设"
  fi
  sep
  echo "  硬盘:${DISK_LINE}"
  echo "  安装目录:${INSTALL_DIR}    媒体目录:${DATA_ROOT}"
}

echo
gen_summary | tee "$CRED_FILE" >/dev/null
chmod 600 "$CRED_FILE"

echo
gen_summary
hr
ok "部署完成!凭据已保存到 ${c_bold}${CRED_FILE}${c_reset}(chmod 600)"
echo
warn "接下来的一次性对接(在各网页里点,脚本无法代劳):"
echo "   1) Prowlarr 添加索引器(你的 BT/PT 站点)→ 再 Add App 连 Sonarr/Radarr"
echo "   2) Sonarr/Radarr:Settings→Download Clients 添加 qBittorrent(主机填 qbittorrent,端口 8080)"
echo "   3) Sonarr/Radarr 媒体库路径填 /data/tv 与 /data/movies;下载路径 /data/downloads"
echo "   4) Emby 添加媒体库,路径指向 /data/movies 、/data/tv"
echo "   5) Jellyseerr 首次登录用 Emby 账号,再连 Sonarr/Radarr"
if [[ "$USE_PROXY" != "yes" ]]; then
  echo
  warn "当前是 IP:端口 模式,端口暴露公网。强烈建议:限制防火墙来源,或重跑本脚本启用域名反代。"
fi
echo
