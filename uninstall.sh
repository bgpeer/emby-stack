#!/usr/bin/env bash
# =============================================================================
#  media-stack 卸载脚本
#  停止并删除所有容器,可选删除配置/媒体数据。绝不触碰宿主机其它服务。
#  用法: sudo bash uninstall.sh
# =============================================================================
set -euo pipefail
c_reset=$'\e[0m'; c_green=$'\e[32m'; c_yellow=$'\e[33m'; c_red=$'\e[31m'; c_cyan=$'\e[36m'
info(){ printf '%s\n' "${c_cyan}>>>${c_reset} $*"; }
ok(){   printf '%s\n' "${c_green}✔${c_reset} $*"; }
warn(){ printf '%s\n' "${c_yellow}⚠${c_reset} $*"; }

[[ "${EUID:-$(id -u)}" -ne 0 ]] && { echo "请用 root 运行"; exit 1; }

# 读取安装目录
DEFAULT_DIR="/opt/media-stack"
read -rp "安装目录 [$DEFAULT_DIR]: " INSTALL_DIR; INSTALL_DIR=${INSTALL_DIR:-$DEFAULT_DIR}

if [[ ! -f "${INSTALL_DIR}/docker-compose.yml" ]]; then
  warn "在 ${INSTALL_DIR} 未找到 docker-compose.yml。"
  read -rp "仍要尝试按容器名删除? [y/N]: " a
  [[ "$a" =~ ^[Yy]$ ]] || exit 0
fi

info "停止并删除容器..."
if [[ -f "${INSTALL_DIR}/docker-compose.yml" ]]; then
  ( cd "$INSTALL_DIR" && docker compose down ) || true
else
  for c in emby qbittorrent sonarr radarr prowlarr bazarr jellyseerr homepage caddy; do
    docker rm -f "$c" >/dev/null 2>&1 || true
  done
fi
ok "容器已删除"

read -rp "$(printf '%s' '删除所有配置和媒体数据?此操作不可逆 [y/N]: ')" wipe
if [[ "$wipe" =~ ^[Yy]$ ]]; then
  read -rp "再次确认:输入 DELETE 删除 ${INSTALL_DIR} 全部数据: " confirm
  if [[ "$confirm" == "DELETE" ]]; then
    rm -rf "$INSTALL_DIR"
    ok "已删除 ${INSTALL_DIR}"
  else
    warn "确认词不符,保留数据。"
  fi
else
  warn "保留配置与媒体数据(${INSTALL_DIR})。以后可重新 deploy.sh 复用。"
fi

read -rp "顺便清理无用的 Docker 镜像和缓存? [y/N]: " prune
[[ "$prune" =~ ^[Yy]$ ]] && { docker image prune -a -f; docker volume prune -f; ok "已清理"; }

ok "卸载完成。宿主机其它服务(如你的代理节点)未受影响。"
