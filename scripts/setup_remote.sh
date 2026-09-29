#!/usr/bin/env bash
# 把本仓库推到 GitHub
#
# 沙箱直连 github.com 被封（DNS 指向黑洞 198.18.0.5），
# 但已验证：经 gh-proxy.com 转发，GitHub API（含 POST）和 git 协议都能通。
# 所以本脚本全程走代理。
#
# 用法：
#   export GITHUB_TOKEN=ghp_xxxx   # classic token，勾 repo
#   bash scripts/setup_remote.sh
#
# 可选环境变量：
#   GITHUB_USER   默认取 token 归属账号
#   REPO_NAME     默认 veggie-arena
#   PRIVATE       默认 true（私有）
#   SKIP_CREATE   目标仓库已存在时设为 true（跳过创建，直接 push）
#
# token 申请：https://github.com/settings/tokens
#   → Generate new token (classic) → 勾 repo（全选子项）
#   注意：fine-grained PAT 默认**不能**创建仓库，会返回 403
set -eu
TOKEN="${GITHUB_TOKEN:-}"
[ -z "$TOKEN" ] && { echo "❌ 请先 export GITHUB_TOKEN=ghp_xxxx"; exit 1; }

PROXY="https://gh-proxy.com"
API="$PROXY/https://api.github.com"
REPO_NAME="${REPO_NAME:-veggie-arena}"
PRIVATE="${PRIVATE:-true}"
SKIP_CREATE="${SKIP_CREATE:-false}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "1) 确认 token 归属账号"
LOGIN=$(curl -s --max-time 20 -H "Authorization: Bearer $TOKEN" "$API/user" \
        | python3 -c "import sys,json;print(json.load(sys.stdin).get('login','?'))")
USER="${GITHUB_USER:-$LOGIN}"
echo "   login = $USER"
[ "$LOGIN" = "?" ] && { echo "❌ token 无效或网络不通"; exit 1; }

if [ "$SKIP_CREATE" != "true" ]; then
  echo "2) 创建远端仓库 $USER/$REPO_NAME (private=$PRIVATE)"
  RESP=$(curl -s --max-time 25 -X POST \
    -H "Authorization: Bearer $TOKEN" -H "Accept: application/vnd.github+json" \
    -d "{\"name\":\"$REPO_NAME\",\"private\":$PRIVATE,\"description\":\"手机竖屏竞技场生存 Roguelite (Godot 4.3)\"}" \
    "$API/user/repos")
  if echo "$RESP" | grep -q '"full_name"'; then
    echo "   ✅ 已创建"
  else
    echo "   ⚠️ 创建失败：$RESP" | head -c 300
    echo ""
    echo "   可能原因：fine-grained token 无创建权限，或仓库已存在。"
    echo "   若是仓库已存在，改用：SKIP_CREATE=true bash scripts/setup_remote.sh"
    exit 1
  fi
fi

echo "3) 推送（经代理）"
PUSH_URL="$PROXY/https://github.com/$USER/$REPO_NAME.git"
AUTH_URL="${PUSH_URL/https:\/\//https:\/\/$USER:$TOKEN@}"
git branch -M main
git push -u "$AUTH_URL" main

echo "4) 落一个干净的 remote（不含 token）"
if git remote get-url origin >/dev/null 2>&1; then
  git remote set-url origin "$PUSH_URL"
else
  git remote add origin "$PUSH_URL"
fi
git remote -v

# 把代理地址记进 .git/config，之后 push 不用再带 token（仍需 credential）
git config pushInsteadOf."https://github.com/" "$PROXY/https://github.com/"

echo ""
echo "✅ 完成：https://github.com/$USER/$REPO_NAME"
echo "   后续推送：git push origin main"
echo "⚠️  建议用完后删除这个 token：https://github.com/settings/tokens"
