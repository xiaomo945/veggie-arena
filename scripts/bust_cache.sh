#!/usr/bin/env bash
# Godot Web 导出缓存击穿 + 保留原文件兜底。
# 用法：导出后执行  bash scripts/bust_cache.sh
# 原理：
#   1) 给 pck/wasm 复制一份带时间戳哈希的副本（index.<ts>.pck / .wasm），
#      并把 index.html 的 executable / fileSizes 指过去 —— 新访问必拉新文件。
#   2) 【关键】保留原始 index.pck / index.wasm 不删除。
#      这样任何还缓存着旧 index.html（executable:"index"）的手机，
#      去要 index.pck 时拿到的是【修复版】，既不 404、也不会吃到旧坏版。
#   服务器不返回 Cache-Control，浏览器会启发式缓存，所以“保留原文件”是兜底。
set -e
DIR="${1:-web/build}"
cd "$(dirname "$0")/.." || exit 1
cd "$DIR"
# 【关键】绝不能删除历史哈希副本！
# CDN 会缓存旧版 index.html（服务器不发 Cache-Control），若旧 html 引用的
# index.<旧哈希>.pck 被删掉，手机就会 404 → 页面打不开。
# 所以：把所有历史哈希文件都用【当前最新构建】覆盖，保证任何旧 html 都拿到最新版。
H=$(date +%s)
for f in index.[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9].pck; do
	[ -e "$f" ] && cp -f index.pck "$f"
done
for f in index.[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9].wasm; do
	[ -e "$f" ] && cp -f index.wasm "$f"
done
cp index.pck "index.$H.pck"
cp index.wasm "index.$H.wasm"
# 注意：不删除 index.pck / index.wasm（见上方说明）
python3 - "$H" <<'PY'
import sys
h=sys.argv[1]
p='index.html'
s=open(p,encoding='utf-8').read()

# ---- 1) 缓存击穿 ----
s=s.replace('"executable":"index"','"executable":"index.%s"'%h)
s=s.replace('"index.pck":','"index.%s.pck":'%h)
s=s.replace('"index.wasm":','"index.%s.wasm":'%h)

# ---- 2) 移动端手势锁：禁止横滑返回 / 下拉刷新 / 橡皮筋 / 长按菜单 ----
# （幂等：带标记，重复执行不会重复插入）
CSS_MARK='/* GESTURE-LOCK */'
if CSS_MARK not in s:
    css = CSS_MARK + """
html, body {
\twidth: 100%;
\theight: 100%;
\toverflow: hidden;
\tposition: fixed;
\toverscroll-behavior: none;
\toverscroll-behavior-x: none;
\toverscroll-behavior-y: none;
\tuser-select: none;
\t-webkit-user-select: none;
\t-webkit-touch-callout: none;
\t-webkit-tap-highlight-color: transparent;
}
#canvas { touch-action: none; }
"""
    s=s.replace('</style>', css + '</style>')

JS_MARK='GESTURE-LOCK-JS'
if JS_MARK not in s:
    js = """
<script>
/* GESTURE-LOCK-JS 禁止浏览器滚动/横滑返回/下拉刷新，保证拖拽只作用于游戏 */
(function () {
\tvar opt = { passive: false };
\tdocument.addEventListener('touchmove', function (e) { e.preventDefault(); }, opt);
\tdocument.addEventListener('touchstart', function (e) {
\t\tif (e.touches.length > 1) { e.preventDefault(); }
\t}, opt);
})();
</script>
"""
    s=s.replace('</body>', js + '</body>')

if 'mobile-web-app-capable' not in s:
    s=s.replace('<meta name="viewport"',
        '<meta name="mobile-web-app-capable" content="yes">\n\t\t'
        '<meta name="apple-mobile-web-app-capable" content="yes">\n\t\t'
        '<meta name="apple-mobile-web-app-status-bar-style" content="black-translucent">\n\t\t'
        '<meta name="viewport"')

open(p,'w',encoding='utf-8').write(s)
print("cache-bust -> index.%s （原文件保留兜底 + 移动端手势锁 + 清理旧哈希）"%h)
PY
