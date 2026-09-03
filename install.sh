#!/usr/bin/env bash
# billion-context-optimized 安装脚本
# 自动检测平台, 从 GitHub Release 下载对应二进制并校验 SHA256, 安装到 ./bin/bili
set -euo pipefail

REPO="ChainZeaxion/billion-context-optimized"
TAG="latest"   # 默认跟踪最新 release; 锁定版本改成具体 tag (如 v0.1)
# 若 TAG=latest, 通过 API 取最新 tag
if [ "$TAG" = "latest" ]; then
  TAG="$(curl -fsSL -H "Accept: application/vnd.github+json" \
      "https://api.github.com/repos/${REPO}/releases/latest" \
      | python3 -c 'import sys,json; print(json.load(sys.stdin)["tag_name"])')"
fi

DL="https://github.com/${REPO}/releases/download/${TAG}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# 检测平台
os="$(uname -s)"
arch="$(uname -m)"
case "$os-$arch" in
  Linux-x86_64)   name="bili-linux-x64";;
  Linux-aarch64)  name="bili-linux-arm64";;
  Darwin-arm64)   name="bili-macos-arm64";;
  Darwin-x86_64)  echo "    警告: Intel macOS 官方仅发布 Apple Silicon 版"; name="bili-macos-arm64";;
  *) echo "    未识别平台 $os-$arch (Windows 请手动下载 .exe)"; exit 1;;
esac

echo "==> 下载 ${name} (${TAG}) ..."
curl -fL --progress-bar -o "$TMP/$name" "$DL/$name"

echo "==> 校验 SHA256 ..."
curl -fsSL -o "$TMP/SHA256SUMS.txt" "$DL/SHA256SUMS.txt"
( cd "$TMP" && grep " ${name}$" SHA256SUMS.txt | sha256sum -c - )

install_dir="$(pwd)/bin"
mkdir -p "$install_dir"
cp "$TMP/$name" "$install_dir/bili"
chmod +x "$install_dir/bili"

echo ""
echo "==> 安装完成: $install_dir/bili"
echo "    运行:   ./bin/bili --port 8878 --host 0.0.0.0"
echo "    接入:   把 agent 的 base URL 前缀加上 http://<host>:8878/bili/"
