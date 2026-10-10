#!/usr/bin/env python3
"""导出后给 web/build/index.html 注入移动端防护（幂等，可重复跑）：

1) body 加 `overscroll-behavior: none;` —— 禁止边缘下拉刷新 / 回弹，
   配合 Godot 模板自带的 `touch-action: none`，让 canvas 内的拖拽/滑动不再被浏览器抢走。
2) 注入 history 守卫脚本 —— 手机从屏幕边缘右滑触发的是系统级"返回"，
   `touch-action` 拦不住；这里多压一层 history 状态，用户误触返回时把它推回去，
   页面不会"唰一下没了"。标准 SPA 防丢页做法。
"""
import sys, pathlib

def main():
    if len(sys.argv) < 2:
        print("usage: patch_web_html.py <build_dir>")
        sys.exit(2)
    html = pathlib.Path(sys.argv[1]) / "index.html"
    if not html.exists():
        print("! 找不到", html, "（导出可能没出成品）")
        sys.exit(1)
    s = html.read_text(encoding="utf-8")

    # 1) overscroll-behavior（直接插在 touch-action 后，避免依赖闭合括号缩进）
    if "overscroll-behavior" not in s:
        s = s.replace(
            "touch-action: none;",
            "touch-action: none;\n\toverscroll-behavior: none;",
            1,
        )

    # 2) history 守卫（注入到 </body> 前，且只注一次）
    guard = """
\t\t<!-- 移动端防丢页：误触边缘返回时把 history 状态推回去，页面不消失 -->
\t\t<script>
\t\t(function () {
\t\t\tfunction guard() { history.pushState(null, '', location.href); }
\t\t\tguard();
\t\t\twindow.addEventListener('load', guard);
\t\t\twindow.addEventListener('popstate', function () { guard(); });
\t\t})();
\t\t</script>
"""
    if "移动端防丢页" not in s:
        s = s.replace("</body>", guard + "</body>", 1)

    # 3) 渲染精度调节（Godot 在 web 上按 canvas.width/height 出图，DPR=3 的手机
    #    一帧要填 1620x2700 ≈ 440 万像素，是"走路发虚/掉帧"的头号嫌疑）。
    #    这里把 canvas 的像素尺寸压到 CSS 尺寸的某个比例，CSS 尺寸不变 ——
    #    浏览器负责拉伸，于是渲染像素数按 s² 下降（0.72 → 只剩 52%）。
    #    Godot 自己 resize 时会把 width/height 改回去，所以用 MutationObserver 顶回去。
    scale = """
\t\t<!-- 渲染精度：低画质时降 canvas 像素数，缓解高 DPI 手机的填充率压力 -->
\t\t<script>
\t\t(function () {
\t\t\twindow.vaScale = 1.0;
\t\t\tfunction apply() {
\t\t\t\tvar c = document.getElementById('canvas');
\t\t\t\tif (!c) return;
\t\t\t\tvar r = c.getBoundingClientRect();
\t\t\t\tvar w = Math.max(1, Math.round(r.width * window.vaScale));
\t\t\t\tvar h = Math.max(1, Math.round(r.height * window.vaScale));
\t\t\t\tif (c.width !== w || c.height !== h) { c.width = w; c.height = h; }
\t\t\t}
\t\t\twindow.vaSetRenderScale = function (v) {
\t\t\t\twindow.vaScale = Math.max(0.5, Math.min(1.0, v || 1.0));
\t\t\t\tapply();
\t\t\t};
\t\t\twindow.addEventListener('resize', function () { setTimeout(apply, 60); });
\t\t\tvar c0 = document.getElementById('canvas');
\t\t\tif (c0 && window.MutationObserver) {
\t\t\t\tnew MutationObserver(apply).observe(c0, {
\t\t\t\t\tattributes: true, attributeFilter: ['width', 'height']
\t\t\t\t});
\t\t\t}
\t\t})();
\t\t</script>
"""
    if "渲染精度" not in s:
        s = s.replace("</body>", scale + "</body>", 1)

    html.write_text(s, encoding="utf-8")
    print("✅ 已注入移动端防护（overscroll-behavior + popstate 守卫）:", html)

if __name__ == "__main__":
    main()
