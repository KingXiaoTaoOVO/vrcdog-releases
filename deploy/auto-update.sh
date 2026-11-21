#!/usr/bin/env bash
# VRCDog 自动更新：比对公开镜像上的版本号，不同就拉部署包并重启容器。
# 装在 /opt/VRCDog/auto-update.sh，由 cron 每 5 分钟调用。
set -u
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

REPO_RAW="https://raw.githubusercontent.com/KingXiaoTaoOVO/vrcdog-releases/main/deploy"
MIRRORS=("https://gh-proxy.com/" "https://ghproxy.net/" "https://ghfast.top/" "")
LOG=/var/log/vrcdog-auto.log
STATE=/opt/VRCDog/.deployed-version
PKG=/tmp/vrcdog-deploy.tgz

log() { echo "$(date '+%F %T') $*" >> "$LOG"; }

fetch() {
  local file="$1" out="$2" timeout="$3" m
  for m in "${MIRRORS[@]}"; do
    if curl -fsSL --connect-timeout 8 --max-time "$timeout" -o "$out" "${m}${REPO_RAW}/${file}" 2>/dev/null; then
      if [ -s "$out" ]; then
        return 0
      fi
    fi
  done
  return 1
}

exec 9>/var/lock/vrcdog-auto.lock
flock -n 9 || exit 0

if [ ! -d /opt/VRCDog ]; then
  log "缺少 /opt/VRCDog，跳过"
  exit 0
fi

tmpv=$(mktemp)
if ! fetch version.txt "$tmpv" 20; then
  log "版本检查失败：所有镜像不可达"
  rm -f "$tmpv"
  exit 0
fi
V=$(tr -d '\r\n' < "$tmpv")
rm -f "$tmpv"
[ -z "$V" ] && exit 0

CUR=$(cat "$STATE" 2>/dev/null || echo none)
if [ "$V" = "$CUR" ]; then
  exit 0
fi

log "发现新版本 $V（当前 $CUR），开始更新"
if ! fetch vrcdog-deploy.tgz "$PKG" 300; then
  log "部署包下载失败"
  exit 1
fi
if ! tar -tzf "$PKG" >/dev/null 2>&1; then
  log "部署包损坏"
  rm -f "$PKG"
  exit 1
fi

rm -rf /tmp/vd-auto
mkdir -p /tmp/vd-auto
if ! tar -xzf "$PKG" -C /tmp/vd-auto; then
  log "解包失败"
  exit 1
fi

cd /opt/VRCDog || exit 1
mkdir -p vrcdog-server/bin
\cp -f /tmp/vd-auto/vrcdog-server/bin/vrcdog-server vrcdog-server/bin/vrcdog-server
chmod +x vrcdog-server/bin/vrcdog-server
\cp -rf /tmp/vd-auto/website-dist/. website-dist/
\cp -f /tmp/vd-auto/deploy-prebuilt.sh deploy-prebuilt.sh
chmod +x deploy-prebuilt.sh

bash deploy-prebuilt.sh >> "$LOG" 2>&1
echo "$V" > "$STATE"
log "更新完成 $V"
