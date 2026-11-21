#!/usr/bin/env bash
# VRCDog 自动更新：比对公开镜像上的版本号，不同就拉部署包并重启容器。
# 装在 /opt/VRCDog/auto-update.sh，由 cron 每 5 分钟调用。
set -u
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

REPO_RAW="https://raw.githubusercontent.com/KingXiaoTaoOVO/vrcdog-releases/main/deploy"
MIRRORS=("https://gh-proxy.com/" "https://ghproxy.net/" "https://ghfast.top/" "")
LOG=/var/log/vrcdog-auto.log
STATE=/opt/VRCDog/.deployed-version
FAILFILE=/opt/VRCDog/.update-failed
PKG=/tmp/vrcdog-deploy.tgz
SUMF=/tmp/vrcdog-deploy.sha256
BIN=/opt/VRCDog/vrcdog-server/bin/vrcdog-server
BACKUP=/opt/VRCDog/vrcdog-server/bin/vrcdog-server.prev

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

# 同一个版本连续失败 3 次就停下来等人工处理，避免每 5 分钟反复把线上打挂。
FAILV=""
FAILN=0
if [ -f "$FAILFILE" ]; then
  FAILV=$(awk -F: 'NR==1 {print $1}' "$FAILFILE")
  FAILN=$(awk -F: 'NR==1 {print $2}' "$FAILFILE")
  case "$FAILN" in ''|*[!0-9]*) FAILN=0 ;; esac
fi
if [ "$FAILV" = "$V" ] && [ "$FAILN" -ge 3 ]; then
  exit 0
fi

log "发现新版本 $V（当前 $CUR），开始更新"
if ! fetch vrcdog-deploy.tgz "$PKG" 300; then
  log "部署包下载失败"
  exit 1
fi

# 有 sha256sum.txt 就强制比对，防止镜像篡改或传输截断。
rm -f "$SUMF"
if fetch sha256sum.txt "$SUMF" 20 && [ -s "$SUMF" ]; then
  EXPECT=$(awk 'NR==1 {print $1}' "$SUMF")
  ACTUAL=$(sha256sum "$PKG" | awk '{print $1}')
  if [ -n "$EXPECT" ] && [ "$EXPECT" != "$ACTUAL" ]; then
    log "校验和不匹配（期望 $EXPECT 实际 $ACTUAL），丢弃本次更新"
    rm -f "$PKG" "$SUMF"
    exit 1
  fi
  log "校验和通过 $ACTUAL"
else
  log "没有校验和文件，跳过校验（旧版发布通道）"
fi
rm -f "$SUMF"

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
if [ -f "$BIN" ]; then
  \cp -f "$BIN" "$BACKUP"
  chmod +x "$BACKUP"
fi
\cp -f /tmp/vd-auto/vrcdog-server/bin/vrcdog-server "$BIN"
chmod +x "$BIN"
\cp -rf /tmp/vd-auto/website-dist/. website-dist/
\cp -f /tmp/vd-auto/deploy-prebuilt.sh deploy-prebuilt.sh
chmod +x deploy-prebuilt.sh

if ! bash deploy-prebuilt.sh >> "$LOG" 2>&1; then
  echo "$V:$((FAILN + 1))" > "$FAILFILE"
  log "部署失败（第 $((FAILN + 1)) 次），尝试回滚到上一个二进制"
  if [ -f "$BACKUP" ]; then
    \cp -f "$BACKUP" "$BIN"
    chmod +x "$BIN"
    if bash deploy-prebuilt.sh >> "$LOG" 2>&1; then
      log "回滚成功，保持版本 $CUR"
    else
      log "回滚也失败了，需要人工介入"
    fi
  else
    log "没有可回滚的备份"
  fi
  exit 1
fi

rm -f "$FAILFILE"
echo "$V" > "$STATE"
log "更新完成 $V"
