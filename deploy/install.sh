#!/usr/bin/env bash
# VRCDog 一键安装自动更新（服务器上执行一次即可）
#   curl -fsSL https://gh-proxy.com/https://raw.githubusercontent.com/KingXiaoTaoOVO/vrcdog-releases/main/deploy/install.sh | bash
set -u
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

REPO_RAW="https://raw.githubusercontent.com/KingXiaoTaoOVO/vrcdog-releases/main/deploy"
MIRRORS=("https://gh-proxy.com/" "https://ghproxy.net/" "https://ghfast.top/" "")
TARGET=/opt/VRCDog/auto-update.sh

fetch() {
  local file="$1" out="$2" m
  for m in "${MIRRORS[@]}"; do
    if curl -fsSL --connect-timeout 8 --max-time 60 -o "$out" "${m}${REPO_RAW}/${file}" 2>/dev/null; then
      [ -s "$out" ] && return 0
    fi
  done
  return 1
}

echo "== 环境检查"
if [ ! -d /opt/VRCDog ]; then
  echo "[x] 没有 /opt/VRCDog，这台不是部署机"
  exit 1
fi
echo "    主机: $(hostname)  出口IP: $(curl -s --max-time 8 https://ifconfig.me || echo 未知)"
echo "    仓库目录: /opt/VRCDog"

echo "== 下载更新脚本"
if ! fetch auto-update.sh "$TARGET"; then
  echo "[x] 三个镜像都不可达，请检查服务器网络"
  exit 1
fi
chmod +x "$TARGET"
echo "    -> $TARGET"

echo "== 安装定时任务（每 5 分钟）"
( crontab -l 2>/dev/null | grep -v 'vrcdog-auto-update' ; echo '*/5 * * * * bash /opt/VRCDog/auto-update.sh # vrcdog-auto-update' ) | crontab -
crontab -l 2>/dev/null | grep 'vrcdog-auto-update'

echo "== 立即执行一次（首次会把线上更新到最新）"
bash "$TARGET"
echo "== 日志"
tail -n 25 /var/log/vrcdog-auto.log 2>/dev/null || echo "（暂无日志）"
echo
echo "完成。以后不再需要手动部署。"
