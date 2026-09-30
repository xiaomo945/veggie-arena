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
# 【重要】历史哈希副本要保留，但不能无限保留 —— 每份 wasm+pck 约 41MB，
# 累积 10 份就是 440MB，会把发布流程拖垮。所以只留最近 KEEP 份：
# 这几份覆盖最近几次发布，更老的缓存由下面的自愈 JS 兜底（自动重载拿最新版）。
# 注意：绝不能删 index.pck / index.wasm 原件 —— 最早的 html 还引用着它们。
KEEP="${KEEP:-3}"
# 按时间戳升序，删掉超出 KEEP 的最老那几份（pck 与 wasm 成对）
for f in $(ls -1 index.[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9].pck 2>/dev/null | sort | head -n -"$KEEP"); do
	rm -f "$f" "${f%.pck}.wasm"
	echo "清理旧哈希副本: $f"
done
H=$(date +%s)
cp index.pck "index.$H.pck"
cp index.wasm "index.$H.wasm"
# 注意：不删除 index.pck / index.wasm（见上方说明）
python3 - "$H" <<'PY'
import sys, re, os
h=sys.argv[1]
p='index.html'
s=open(p,encoding='utf-8').read()

# ---- 1) 缓存击穿 ----
# 必须写成"幂等的正则"：上一次执行已经把 executable 换成了 index.<旧哈希>，
# 若还用 replace('"executable":"index"', ...) 第二次就匹配不上，
# 结果 index.html 一直指着旧哈希 —— 发新版却加载旧资源。踩过一次。
s=re.sub(r'"executable":"index(?:\.\d+)?"', '"executable":"index.%s"'%h, s)
s=re.sub(r'"index(?:\.\d+)?\.pck":', '"index.%s.pck":'%h, s)
s=re.sub(r'"index(?:\.\d+)?\.wasm":', '"index.%s.wasm":'%h, s)

# progress.fileSizes 里的体积换成真实值（键名同上，值也要跟着走）
for ext in ('pck', 'wasm'):
    try:
        size = os.path.getsize('index.%s.%s' % (h, ext))
    except OSError:
        continue
    s=re.sub(r'("index\.%s\.%s":\s*)\d+' % (h, ext), r'\g<1>%d' % size, s)

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

# ---- 3) 自愈：老缓存 html 引用的哈希文件已被清理时，自动重载拿最新版 ----
# 场景：手机缓存了 3 次发布前的 index.html，它要 index.<旧哈希>.pck，而这文件
# 已经不在了 → 以前是白屏。现在捕获到 404，换个 URL 参数强刷一次（=绕过缓存）。
# 只做一次：用 sessionStorage 打标记，否则会陷入无限重载。
HEAL_MARK='SELF-HEAL-JS'
if HEAL_MARK not in s:
    heal = """
<script>
/* SELF-HEAL-JS 资源 404 时自动重载一次，救回"缓存着旧 html 的手机" */
(function () {
\tif (window.sessionStorage && sessionStorage.getItem('__tt_healed')) { return; }
\tfunction heal() {
\t\tif (window.sessionStorage) { sessionStorage.setItem('__tt_healed', '1'); }
\t\tsetTimeout(function () {
\t\t\tlocation.href = location.pathname + '?_=' + Date.now();
\t\t}, 300);
\t}
\tvar _fetch = window.fetch;
\tif (_fetch) {
\t\twindow.fetch = function () {
\t\t\tvar url = arguments[0];
\t\t\treturn _fetch.apply(window, arguments).then(function (r) {
\t\t\t\tif (!r.ok && String(url).indexOf('index.') >= 0) { heal(); }
\t\t\t\treturn r;
\t\t\t});
\t\t};
\t}
\tvar _open = XMLHttpRequest.prototype.open;
\tXMLHttpRequest.prototype.open = function (m, u) { this.__u = u; return _open.apply(this, arguments); };
\tvar _send = XMLHttpRequest.prototype.send;
\tXMLHttpRequest.prototype.send = function () {
\t\tvar self = this;
\t\tthis.addEventListener('loadend', function () {
\t\t\tif (self.status === 404 && String(self.__u).indexOf('index.') >= 0) { heal(); }
\t\t});
\t\treturn _send.apply(this, arguments);
\t};
})();
</script>
"""
    s=s.replace('</body>', heal + '</body>')

open(p,'w',encoding='utf-8').write(s)
print("cache-bust -> index.%s （原文件保留兜底 + 移动端手势锁 + 清理旧哈希）"%h)
PY
