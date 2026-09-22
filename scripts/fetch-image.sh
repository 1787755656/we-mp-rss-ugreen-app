#!/usr/bin/env bash
# 拉上游镜像并导出为 docker-save tar(ugcli 只认带 manifest.json 的格式)
# 用法: scripts/fetch-image.sh <amd64|arm64> <版本号>
#
# 上游只发 latest,没有版本 tag。不能「pull latest → tag → save」一气呵成:
# colima/新版 Docker 的 containerd 镜像存储下,tag 钉住的是多架构 index,
# save 会把另一个平台的 manifest 一起写进 tar 甚至直接报 digest not found。
# 稳的写法:先解析 latest 的 per-arch manifest digest,按 digest 拉取(两种
# 存储都成立),再 retag 成版本号,使 tar 里 RepoTags 与 compose 镜像引用一致。
set -euo pipefail
cd "$(dirname "$0")/.."

ARCH="${1:?用法: fetch-image.sh <amd64|arm64> <版本号>}"
VER="${2:?用法: fetch-image.sh <amd64|arm64> <版本号>}"
case "$ARCH" in amd64|arm64) ;; *) echo "!! 架构只能是 amd64 或 arm64" >&2; exit 1 ;; esac

REPO="rachelos/we-mp-rss"
IMAGE="ghcr.io/${REPO}"

TOKEN_URL="https://ghcr.io/token?scope=repository:${REPO}:pull"
AUTH_JSON=$(curl -fsSL "${TOKEN_URL}")
AUTH=$(printf '%s' "${AUTH_JSON}" | jq -r .token)
ACCEPT="application/vnd.oci.image.index.v1+json, application/vnd.docker.distribution.manifest.list.v2+json, application/vnd.oci.image.manifest.v1+json, application/vnd.docker.distribution.manifest.v2+json"
IDX=$(curl -fsSL -H "Authorization: Bearer ${AUTH}" -H "Accept: ${ACCEPT}" "https://ghcr.io/v2/${REPO}/manifests/latest")

DIGEST=$(echo "$IDX" | jq -r "[.manifests[] | select(.platform.os==\"linux\" and .platform.architecture==\"${ARCH}\")][0].digest // empty")
if [ -z "$DIGEST" ]; then
  # 非 index(单架构 manifest)直接取 config digest
  DIGEST=$(echo "$IDX" | jq -r 'if .manifests then empty else .config.digest end')
fi
[ -n "$DIGEST" ] || { echo "!! 解析不到 ${ARCH} 的 digest" >&2; exit 1; }
echo "==> ${ARCH} digest: ${DIGEST}"

docker pull "${IMAGE}@${DIGEST}"
docker tag "${IMAGE}@${DIGEST}" "${IMAGE}:${VER}"

OUT="com.rachelos.wemprss/rootfs_${ARCH}/images/we-mp-rss-${VER}.tar"
mkdir -p "$(dirname "$OUT")"
docker save "${IMAGE}:${VER}" -o "$OUT"

# 自检 1: legacy manifest.json 存在且 RepoTags 与 compose 引用一致
tar -xOf "$OUT" manifest.json | jq -e '.[0].RepoTags | index("'"${IMAGE}:${VER}"'")' >/dev/null \
  || { echo "!! tar 里 RepoTags 不是 ${IMAGE}:${VER}" >&2; exit 1; }
# 自检 2: config 的 architecture 必须一致
CONFIG=$(tar -xOf "$OUT" manifest.json | jq -r '.[0].Config')
TAR_ARCH=$(tar -xOf "$OUT" "$CONFIG" | jq -r .architecture)
case "$ARCH" in
  amd64) [ "$TAR_ARCH" = "amd64" ] || [ "$TAR_ARCH" = "x86_64" ] || { echo "!! tar 是 ${TAR_ARCH},要 amd64" >&2; exit 1; } ;;
  arm64) [ "$TAR_ARCH" = "arm64" ] || [ "$TAR_ARCH" = "aarch64" ] || { echo "!! tar 是 ${TAR_ARCH},要 arm64" >&2; exit 1; } ;;
esac
echo "==> 导出完成 $(du -h "$OUT" | cut -f1): ${OUT}"
