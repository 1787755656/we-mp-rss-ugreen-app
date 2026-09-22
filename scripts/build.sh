#!/usr/bin/env bash
# WeRSS UGOS 应用打包(本地与 CI 共用)
# 用法: scripts/build.sh <构建号> [架构...]
#   构建号: 十进制纯数字(不要前导零,ugcli 会按八进制解析),同一版本下只能升
#   架构:   缺省 amd64 arm64
set -euo pipefail
cd "$(dirname "$0")/.."

APP_ID="com.rachelos.wemprss"
APP_DIR="$APP_ID"

# CI(Linux x86_64)用仓库内 vendored 的 ugcli(不依赖绿联 CDN);
# macOS 本地开发用本机安装的 darwin 版(Linux ELF 在 mac 上跑不了)
HOST_OS=$(uname -s); HOST_ARCH=$(uname -m)
if [ "$HOST_OS" = "Linux" ] && [ "$HOST_ARCH" = "x86_64" ]; then
  UGCLI_BIN="$(pwd)/tools/ugcli/ugcli-linux-amd64"
else
  UGCLI_BIN="${UGCLI_BIN:-$HOME/bin/ugcli}"
  [ -x "$UGCLI_BIN" ] || UGCLI_BIN="$HOME/Desktop/绿联开发/ugcli-v1.1.0.25-darwin-arm64"
fi

BUILD="${1:?用法: build.sh <构建号> [架构...]}"
case "$BUILD" in *[!0-9]*|'') echo "!! 构建号必须是纯数字: $BUILD" >&2; exit 1;; esac
shift || true
ARCHS=("$@"); [ ${#ARCHS[@]} -eq 0 ] && ARCHS=(amd64 arm64)

VERSION=$(awk '/^version:/{print $2; exit}' "$APP_DIR/project.yaml")

# 守卫:compose 里的镜像 tag 必须与 project.yaml 版本一致(bump 时两处要同步)
COMPOSE_TAG=$(grep -oE 'rachelos/we-mp-rss:[0-9.]+' "$APP_DIR/rootfs_common/docker-compose.yaml" | head -1 | cut -d: -f2)
if [ "$COMPOSE_TAG" != "$VERSION" ]; then
  echo "!! 版本不一致: project.yaml=${VERSION} compose 镜像 tag=${COMPOSE_TAG}" >&2
  exit 1
fi

# Docker 型应用:两架构目录只允许 images/,且每个 service 的镜像必须有
# 对应的 docker save tar(<镜像名>-<tag>.tar,check 会解析 manifest.json)。
# CI 里由 workflow 先 docker pull + save;本地打包前先自己准备(见 README)。
for a in "${ARCHS[@]}"; do
  mkdir -p "$APP_DIR/rootfs_${a}/images"
  TAR="$APP_DIR/rootfs_${a}/images/we-mp-rss-${VERSION}.tar"
  if [ ! -s "$TAR" ]; then
    echo "!! 缺镜像 tar: $TAR" >&2
    echo "   先拉镜像并导出(上游只发 latest,拉下来 retag 成版本号):" >&2
    echo "   docker pull --platform linux/${a} ghcr.io/rachelos/we-mp-rss:latest" >&2
    echo "   docker tag ghcr.io/rachelos/we-mp-rss:latest ghcr.io/rachelos/we-mp-rss:${VERSION}" >&2
    echo "   docker save ghcr.io/rachelos/we-mp-rss:${VERSION} -o $TAR" >&2
    exit 1
  fi
done

chmod +x "$UGCLI_BIN"

echo "==> ugcli check (${VERSION})"
(
  cd "$APP_DIR"
  "$UGCLI_BIN" check
)

echo "==> ugcli pack 构建号 ${BUILD} 架构 ${ARCHS[*]}"
for a in "${ARCHS[@]}"; do
  (
    cd "$APP_DIR"
    "$UGCLI_BIN" pack --arch "$a" --build "$BUILD"
  )
done

# 产物提到仓库根目录,并按【完整构建号】清掉旧包只留最新
FULL="${VERSION}.$(printf '%04d' "$BUILD")"
rm -f ./*_"${APP_ID}"_*.upk
FOUND=0
while IFS= read -r -d '' f; do
  cp "$f" ./
  FOUND=$((FOUND+1))
done < <(find "$APP_DIR/build_dir/pkgs/upk" -name "*_${APP_ID}_${FULL}.upk" -print0)

if [ "$FOUND" -eq 0 ]; then
  echo "!! 没找到 ${FULL} 的 upk,pack 实际产物:" >&2
  ls -la "$APP_DIR/build_dir/pkgs/upk/" 2>/dev/null || true
  exit 1
fi
echo "==> 完成:"
ls -la ./*.upk
