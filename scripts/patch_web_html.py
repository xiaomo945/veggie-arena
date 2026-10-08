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

    html.write_text(s, encoding="utf-8")
    print("✅ 已注入移动端防护（overscroll-behavior + popstate 守卫）:", html)

if __name__ == "__main__":
    main()
