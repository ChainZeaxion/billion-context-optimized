#!/usr/bin/env bash
# billion-context-optimized 安装脚本
# 自动检测平台, 从 GitHub Release 下载对应二进制并校验 SHA256, 安装到 ./bin/bili
set -euo pipefail

REPO="ChainZeaxion/billion-context-optimized"
# 用 latest release 的 tag; 若要锁定版本, 把 latest 换成具体 tag (如 v0.1)
API="https://api.github.com/repos/${REPO}/releases/latest"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "==> 获取最新 Release 信息 ..."
assets_json="$(curl -fsSL "$API/assets")"
base_url="$(python3 - "$assets_json" <<'PY'
import sys, json
data = json.load(sys.stdin)
print(data[0]["url"])
PY
)"
echo "    基准 URL: $base_url"

# 检测平台
os="$(uname -s)"
arch="$(uname -m)"
case "$os-$arch" in
  Linux-x86_64)   name="bili-linux-x64";;
  Linux-aarch64)  name="bili-linux-arm64";;
  Darwin-arm64)   name="bili-macos-arm64";;
  Darwin-x86_64)  echo "    警告: 当前为 Intel macOS, 官方仅发布 Apple Silicon 版, 尝试 arm64"; name="bili-macos-arm64";;
  *) echo "    未识别平台 $os-$arch (Windows 请手动下载 .exe)"; exit 1;;
esac

url="${base_url%/*}/${name}"
echo "==> 下载 $name ..."
curl -fL --progress-bar -o "$TMP/$name" "$url"

# 校验: 拉取 SHA256SUMS.txt 精确比对
echo "==> 校验 SHA256 ..."
sha_file="$(python3 - "$assets_json" <<'PY'
import sys, json
data = json.load(sys.stdin)
for a in data:
    if a["name"] == "SHA256SUMS.txt":
        print(a["url"]); break
PY
)"
curl -fsSL "$sha_file" -o "$TMP/SHA256SUMS.txt"
grep " ${name}$" "$TMP/SHA256SUMS.txt" | ( cd "$TMP" && sha256sum -c - )

install_dir="$(pwd)/bin"
mkdir -p "$install_dir"
cp "$TMP/$name" "$install_dir/bili"
chmod +x "$install_dir/bili"

echo ""
echo "==> 安装完成: $install_dir/bili"
echo "    运行: ./bin/bili --port 8878 --host 0.0.0.0"
echo "    接入: 把 agent 的 base URL 前缀加上 http://<host>:8878/bili/"
