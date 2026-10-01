#!/usr/bin/env bash
# 推送前自愈检查 —— 一条命令完成"重新检查 → 再推送"。
#
# 【为什么需要这个脚本】
# 沙箱休眠会重置 /etc/hosts，github.com 的直连 IP 记录随之消失；此时 git push
# 会在 TLS 握手阶段失败（gnutls_handshake() failed），报错信息完全看不出是 DNS
# 问题，很容易误判成"令牌失效"或"仓库没权限"。
# 所以推送前必须按固定顺序把环境重新检查一遍，坏了就自愈，再推送。
#
# 检查顺序（任一步失败即中止，不做任何推送）：
#   1. 仓库身份   —— 当前目录必须是 veggie-arena，remote 必须是预期仓库
#   2. 全量自检   —— scripts/check.sh（语法/主场景/字体/架构守卫/433 单测/整局集成）
#   3. 网络自愈   —— 连不上 GitHub 就用 DoH 重新解析并写 hosts（含持久化）
#   4. 令牌校验   —— 用真令牌打 api.github.com/user，确认身份与权限
#   5. 推送       —— git push
#   6. 落库校验   —— 比对远端 HEAD 与本地 HEAD，确认真的推上去了
#
# 用法：
#   bash scripts/push.sh                 # 检查 + 推送（工作区必须干净）
#   bash scripts/push.sh -m "提交说明"    # 先提交全部改动，再检查 + 推送
#   bash scripts/push.sh --no-check      # 跳过全量自检（仅限紧急修补，不推荐）
#
# hosts 持久化：沙箱重启会重置 /etc/hosts，但会保留 ~/.user_hosts 的内容。
# 所以解析结果同时写两个文件，避免每次休眠后都要手工修一次。

set -u

REPO_OWNER="xiaomo945"
REPO_NAME="veggie-arena"
EXPECT_REMOTE="https://github.com/${REPO_OWNER}/${REPO_NAME}.git"
HOSTS="/etc/hosts"
USER_HOSTS="${HOME}/.user_hosts"
DOH="https://dns.alidns.com/resolve"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 1

say() { printf '%s\n' "$*"; }
die() { printf '\n❌ %s\n' "$*"; exit 1; }

COMMIT_MSG=""
RUN_CHECK=1
while [ $# -gt 0 ]; do
	case "$1" in
		-m|--message) shift; COMMIT_MSG="${1:-}" ;;
		--no-check) RUN_CHECK=0 ;;
		-h|--help) sed -n '2,30p' "$0"; exit 0 ;;
		*) die "未知参数: $1（用法见 scripts/push.sh 顶部注释）" ;;
	esac
	shift
done

echo "=== 1. 仓库身份 ==="
CUR_REMOTE="$(git remote get-url origin 2>/dev/null || echo "")"
[ "$CUR_REMOTE" = "$EXPECT_REMOTE" ] \
	|| die "remote 不是预期仓库：当前 [$CUR_REMOTE]，期望 [$EXPECT_REMOTE]"
BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")"
[ -n "$BRANCH" ] || die "拿不到当前分支名"
say "  ✅ ${REPO_OWNER}/${REPO_NAME} @ ${BRANCH}"

if [ -n "$COMMIT_MSG" ]; then
	echo ""
	echo "=== 1.5 提交改动 ==="
	if [ -z "$(git status --porcelain)" ]; then
		say "  （工作区干净，无需提交）"
	else
		git add -A || die "git add 失败"
		printf '%s' "$COMMIT_MSG" > /tmp/_push_msg.txt
		git commit -F /tmp/_push_msg.txt -q || die "git commit 失败"
		say "  ✅ 已提交：$(git log --oneline -1)"
	fi
elif [ -n "$(git status --porcelain)" ]; then
	die "工作区有未提交改动。请先提交（bash scripts/push.sh -m \"说明\"），"
fi

if [ "$RUN_CHECK" -eq 1 ]; then
	echo ""
	echo "=== 2. 全量自检（check.sh）==="
	bash scripts/check.sh || die "自检未通过 —— 不允许推送（紧急修补可用 --no-check，但不推荐）"
else
	echo ""
	echo "=== 2. 全量自检：已跳过（--no-check）==="
fi

echo ""
echo "=== 3. 网络自愈（沙箱休眠会重置 hosts）==="
probe() {
	curl -sS --max-time 12 -o /dev/null -w '%{http_code}' \
		"https://api.github.com/" 2>/dev/null
}
# 判定标准只看"连没连上"：TLS 握手失败时 curl 写 000；拿到任何 HTTP 状态码
# （200 / 301 / 401 / 403 ...）都说明链路是通的，只是这个 URL 的语义不同。
reachable() {
	local c
	c="$(probe)"
	[ -n "$c" ] && [ "$c" != "000" ] && [ "$c" != "" ]
}
code="$(probe)"
if [ "$code" != "000" ] && [ -n "$code" ]; then
	say "  ✅ GitHub 可达（HTTP $code）"
else
	say "  ⚠ GitHub 不可达（curl 返回 [$code]）—— 重新解析 DNS"
	resolve() {
		curl -sS --max-time 12 "${DOH}?name=${1}&type=A" 2>/dev/null \
			| grep -oE '"data":"[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+"' \
			| head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+'
	}
	IP_GH="$(resolve github.com)"
	IP_API="$(resolve api.github.com)"
	[ -n "$IP_GH" ] || die "DoH 解析 github.com 失败（网络整体不通？）"
	[ -n "$IP_API" ] || IP_API="$IP_GH"
	say "  ✅ 解析结果：github.com=$IP_GH  api.github.com=$IP_API"

	# 用 python 重写（原子、能正确去重）：直接 grep + mv 在 /etc/hosts 上会静默失败，
	# 结果留下多条重复记录，反而更难排查。
	PYBIN="$(command -v python3.11 || command -v python3)"
	for f in "$HOSTS" "$USER_HOSTS"; do
		if [ -f "$f" ] || [ "$f" = "$USER_HOSTS" ]; then
			out=$("$PYBIN" - "$f" "$IP_GH" "$IP_API" <<'PY'
import sys
path, gh, api = sys.argv[1], sys.argv[2], sys.argv[3]
keep = []
try:
    with open(path, encoding='utf-8', errors='ignore') as fh:
        for ln in fh:
            parts = ln.split()
            if len(parts) >= 2 and parts[1] in ('github.com', 'api.github.com'):
                continue
            keep.append(ln.rstrip('\n'))
except FileNotFoundError:
    pass
keep += ['%s github.com' % gh, '%s api.github.com' % api]
try:
    with open(path, 'w', encoding='utf-8') as fh:
        fh.write('\n'.join(keep) + '\n')
    print('ok')
except Exception as e:
    print('fail: %s' % e)
PY
)
			if [ "$out" = "ok" ]; then
				say "  ✅ 已写入 $f"
			else
				say "  ⚠ 写入 $f 失败（$out）—— 继续尝试直连"
			fi
		fi
	done
	code="$(probe)"
	[ "$code" != "000" ] && [ -n "$code" ] \
		|| die "修完 hosts 仍连不上 GitHub（curl 返回 [$code]）—— 先解决网络再推"
	say "  ✅ 自愈后 GitHub 可达（HTTP $code）"
fi

echo ""
echo "=== 4. 令牌校验 ==="
# 从 git credential helper 取真令牌（不硬编码），拿不到再退回 ~/.git-credentials
TOKEN="$(printf 'protocol=https\nhost=github.com\n\n' | git credential fill 2>/dev/null \
	| awk -F= '/^password=/{print $2; exit}')"
if [ -z "$TOKEN" ] && [ -f "${HOME}/.git-credentials" ]; then
	TOKEN="$(grep -oE '(ghp|github_pat)_[A-Za-z0-9_]+' "${HOME}/.git-credentials" | head -1)"
fi
[ -n "$TOKEN" ] || die "拿不到 GitHub 令牌（git credential fill 与 ~/.git-credentials 都没有）"
who="$(curl -sS --max-time 12 -H "Authorization: Bearer ${TOKEN}" \
	-H "Accept: application/vnd.github+json" \
	"https://api.github.com/user" 2>/dev/null)"
login="$(printf '%s' "$who" | grep -oE '"login" *: *"[^"]+"' | head -1 | cut -d'"' -f4)"
[ -n "$login" ] || die "令牌无效或已过期（api.github.com/user 没返回 login）"
[ "$login" = "$REPO_OWNER" ] || die "令牌身份是 [$login]，与预期仓库主 [$REPO_OWNER] 不符"
say "  ✅ 令牌有效：${login}（${REPO_OWNER}/${REPO_NAME}）"

echo ""
echo "=== 5. 推送 ==="
LOCAL="$(git rev-parse HEAD)"
git push origin "$BRANCH" || die "git push 失败（上面网络/令牌都已检查过，看具体报错）"
say "  ✅ 已推送 $(git log --oneline -1)"

echo ""
echo "=== 6. 落库校验（远端 HEAD 是否与本地一致）==="
REMOTE_SHA="$(curl -sS --max-time 12 -H "Authorization: Bearer ${TOKEN}" \
	-H "Accept: application/vnd.github+json" \
	"https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/commits/${BRANCH}" 2>/dev/null \
	| grep -oE '"sha" *: *"[0-9a-f]{40}"' | head -1 | grep -oE '[0-9a-f]{40}')"
if [ -z "$REMOTE_SHA" ]; then
	say "  ⚠ 拿不到远端 HEAD（可能是权限或限流），跳过比对"
elif [ "$REMOTE_SHA" = "$LOCAL" ]; then
	say "  ✅ 远端 HEAD = 本地 HEAD（${LOCAL:0:9}）"
else
	die "远端 HEAD ${REMOTE_SHA:0:9} ≠ 本地 ${LOCAL:0:9} —— 没真正推上去"
fi

echo ""
echo "=== ✅ 推送完成 ==="
echo "  https://github.com/${REPO_OWNER}/${REPO_NAME}/commits/${BRANCH}"
