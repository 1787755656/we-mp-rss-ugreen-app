#!/usr/bin/env bash
# 查询上游最新 release,输出可用于 project.yaml 的版本号。
# 本地可直接跑(纯 curl + jq):
#   scripts/get-latest-version.sh            # 输出 key=value 行
#   eval "$(scripts/get-latest-version.sh)"  # 得到 $VERSION / $PROJECT_VERSION
#
# 版本概念分两个,不要混用:
#   version          上游完整版本(去 v 前缀),用于 tag 去重与比较
#   project_version  写进 project.yaml 的版本(ugcli 隐藏校验:中段最多两位,
#                    首末段不限;上游若出现超限段需要在这里做确定性映射,
#                    同一上游版本必须永远映射出同一 project 版本)
set -euo pipefail

UPSTREAM_REPO="rachelos/we-mp-rss"

TAG=$(curl -fsSL "https://api.github.com/repos/${UPSTREAM_REPO}/releases/latest" | jq -r '.tag_name')
if [ -z "$TAG" ] || [ "$TAG" = "null" ]; then
  echo "!! 拿不到上游最新 release tag" >&2
  exit 1
fi

V="${TAG#v}"
IFS='.' read -r MA MI PA <<< "$V"
PA="${PA:-0}"
case "${MA}${MI}${PA}" in
  *[!0-9]*) echo "!! 上游版本号非纯数字: ${TAG}" >&2; exit 1 ;;
esac

PROJECT_VERSION="${MA}.${MI}.${PA}"
if [ "${#MI}" -gt 2 ]; then
  echo "!! 上游 minor 段 ${MI} 超过两位,ugcli 会拒绝;请在本脚本里加确定性映射再发版" >&2
  exit 1
fi

echo "version=${MA}.${MI}.${PA}"
echo "project_version=${MA}.${MI}.${PA}"
