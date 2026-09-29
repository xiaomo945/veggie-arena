#!/usr/bin/env bash
# 一键把本仓库推到 GitHub
#
# 用法（二选一）：
#   1) 先 export 再跑：   export GITHUB_TOKEN=ghp_xxxx && bash scripts/setup_remote.sh
#   2) 直接跟在后面：     GITHUB_TOKEN=ghp_xxxx bash scripts/setup_remote.sh
#
# token 申请：https://github.com/settings/tokens → Generate new token (classic) → 勾 repo
# 可选环境变量：REPO_NAME（默认 veggie-arena）、PRIVATE（默认 true，私有仓库）
set -eu
TOKEN="${GITHUB_TOKEN:-}"
REPO_NAME="${REPO_NAME:-veggie-arena}"
PRIVATE="${PRIVATE:-true}"
USER="${GITHUB_USER:-xiaomo945}"

if [ -z "$TOKEN" ]; then
  echo "❌ 请先提供 token：GITHUB_TOKEN=ghp_xxxx bash scripts/setup_remote.sh"
  exit 1
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# 远端地址内嵌 token（用完即清理历史，token 不落盘）
REMOTE="https://${USER}:${TOKEN}@github.com/${USER}/${REPO_NAME}.git"

echo "1) 创建远端仓库 ${USER}/${REPO_NAME}（private=${PRIVATE}）"
curl -s -o /dev/null -w "   HTTP %{http_code}\n" \
  -H "Authorization: token ${TOKEN}" \
  -H "Accept: application/vnd.github+json" \
  -d "{\"name\":\"${REPO_NAME}\",\"private\":${PRIVATE},\"description\":\"手机竖屏竞技场生存 Roguelite（Godot 4.3）\"}" \
  https://api.github.com/user/repos

echo "2) 推送"
if git remote get-url origin >/dev/null 2>&1; then
  git remote set-url origin "$REMOTE"
else
  git remote add origin "$REMOTE"
fi
git branch -M main
git push -u origin main

echo "3) 清理含 token 的远端地址（改回干净形式）"
git remote set-url origin "https://github.com/${USER}/${REPO_NAME}.git"
git remote -v

echo ""
echo "✅ 完成：https://github.com/${USER}/${REPO_NAME}"
echo "⚠️  建议现在去 GitHub 把刚才那个 token 删掉（Settings → Developer settings → Tokens）"
