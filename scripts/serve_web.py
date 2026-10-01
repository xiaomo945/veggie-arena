#!/usr/bin/env python3
"""本地/预览用的静态服务器 —— 带 gzip / brotli 压缩。

为什么不用 `python3 -m http.server`：
    Godot Web 导出的 index.wasm 有 35MB、index.pck 有 7MB，不压缩就是 41MB 首屏。
    4G 下要半分钟以上，手机浏览器还会转圈。开 brotli 后约 12MB，快 3 倍多。
    手感调试要反复刷新，这个差别直接影响你能不能愉快地试玩。

做法：启动时把 web/build 里的大文件预压成 .gz / .br 副本，之后按浏览器的
Accept-Encoding 选一个发回去。预压只做一次，之后请求几乎零开销。

用法：
    python3 scripts/serve_web.py [port]
"""
import os
import sys
import gzip
import shutil
import threading
import functools
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer

try:
    import brotli
except ImportError:
    brotli = None

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "web", "build"))

# 小于这个体积不值得压缩（省得给几百字节的文件也造副本）
MIN_COMPRESS = 1024

TYPES = {
    ".html": "text/html; charset=utf-8",
    ".js": "text/javascript; charset=utf-8",
    ".wasm": "application/wasm",
    ".pck": "application/octet-stream",
    ".png": "image/png",
    ".jpg": "image/jpeg",
    ".svg": "image/svg+xml",
    ".json": "application/json",
    ".ogg": "audio/ogg",
    ".mp3": "audio/mpeg",
    ".css": "text/css; charset=utf-8",
}


def content_type(path: str) -> str:
    return TYPES.get(os.path.splitext(path)[1].lower(), "application/octet-stream")


def make_variant(src: str, dst: str) -> bool:
    """生成一份压缩副本。已存在且不比源旧就跳过。"""
    if os.path.exists(dst) and os.path.getmtime(dst) >= os.path.getmtime(src):
        return False
    tmp = dst + ".tmp"
    try:
        with open(src, "rb") as f:
            data = f.read()
        if dst.endswith(".br"):
            if brotli is None:
                return False
            # 大文件别用最高档：34MB 的 wasm 在 q11 下要几分钟，q9 只要几十秒，
            # 而体积差别只有百分之几 —— 首屏要的是"快点拿到"，不是"再小 200KB"
            q = 9 if len(data) > 8 * 1024 * 1024 else 11
            out = brotli.compress(data, quality=q)
        else:
            out = gzip.compress(data, 9)
        with open(tmp, "wb") as f:
            f.write(out)
        shutil.move(tmp, dst)
        return True
    except Exception as e:  # 压缩失败不该让服务器起不来
        print("  ! 压缩失败 %s: %s" % (os.path.basename(src), e))
        if os.path.exists(tmp):
            os.remove(tmp)
        return False


def target_files(root: str):
    for name in sorted(os.listdir(root)):
        p = os.path.join(root, name)
        if not os.path.isfile(p) or name.endswith((".gz", ".br", ".tmp")):
            continue
        if os.path.getsize(p) < MIN_COMPRESS:
            continue
        yield name, p


def precompress_gz(root: str) -> None:
    """同步做：gzip 很快（35MB 约 1 秒），服务一起来就有压缩可用。"""
    if not os.path.isdir(root):
        print("  ! 目录不存在：%s（先跑一次导出）" % root)
        return
    for name, p in target_files(root):
        made = make_variant(p, p + ".gz")
        gz = p + ".gz"
        if os.path.exists(gz):
            print("  %-24s %6.1f MB -> %5.1f MB (gzip%s)" % (
                name, os.path.getsize(p) / 1048576, os.path.getsize(gz) / 1048576,
                "" if made else ", 已缓存"))


def precompress_br(root: str) -> None:
    """异步做：brotli 高质量压 35MB 要几十秒，但不压就白白慢 3 倍，值得等。"""
    for name, p in target_files(root):
        before = os.path.getsize(p)
        if make_variant(p, p + ".br"):
            br = p + ".br"
            print("  %-24s %6.1f MB -> %5.1f MB (br)" % (
                name, before / 1048576, os.path.getsize(br) / 1048576))
    print("  brotli 预压完成")


class Handler(SimpleHTTPRequestHandler):
    """按 Accept-Encoding 挑一个已压缩的副本发出去。"""

    def send_head(self):
        path = self.translate_path(self.path)
        if not os.path.isfile(path):
            return super().send_head()

        enc = None
        accept = self.headers.get("Accept-Encoding", "")
        # 后台线程可能正在写 .br，用 .tmp 存在与否判断"还没写完"，避免发出半个文件
        br = path + ".br"
        gz = path + ".gz"
        if brotli is not None and "br" in accept and os.path.isfile(br) \
                and not os.path.isfile(br + ".tmp"):
            path = br
            enc = "br"
        elif "gzip" in accept and os.path.isfile(gz) and not os.path.isfile(gz + ".tmp"):
            path = gz
            enc = "gzip"

        f = open(path, "rb")
        # 原始文件的类型/时间才是"内容本身"的信息，压缩副本只是同一内容的另一种编码
        orig = path[:-3] if enc else path
        try:
            st = os.stat(orig)
        except OSError:
            st = os.stat(path)

        self.send_response(200)
        self.send_header("Content-Type", content_type(orig))
        self.send_header("Content-Length", str(os.path.getsize(path)))
        if enc:
            self.send_header("Content-Encoding", enc)
            self.send_header("Vary", "Accept-Encoding")
        self.send_header("Last-Modified", self.date_time_string(int(st.st_mtime)))
        # 预览时永远别缓存住旧包 —— 改完刷新就能看到新的
        self.send_header("Cache-Control", "no-cache, must-revalidate")
        self.end_headers()
        return f

    def log_message(self, fmt, *args):
        # 只打印主资源，省得刷屏
        msg = fmt % args
        if any(k in msg for k in (".wasm", ".pck", ".html", ".js", "code 404")):
            sys.stderr.write("  %s - %s\n" % (self.address_string(), msg))


def main() -> None:
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 3000
    if not os.path.isdir(ROOT):
        print("没有构建产物：%s" % ROOT)
        print("先跑： godot --headless --path . --export-release \"Web\"")
        sys.exit(1)
    # 后台预压：35MB 的 wasm 用 brotli 高质量要压几十秒，不能让它堵住启动。
    # 压好之前请求会先走 gzip 或原始文件，压完自动升级到 brotli。
    print("=== 预压缩 gzip（同步，很快）===", flush=True)
    precompress_gz(ROOT)
    if brotli is None:
        print("  ! 没装 brotli，只用 gzip（pip install brotli 可再快一截）")
    else:
        threading.Thread(target=precompress_br, args=(ROOT,), daemon=True).start()
    # ⚠️ 必须把 directory 显式传进去：SimpleHTTPRequestHandler 默认服务"当前工作目录"，
    # 不传就会 404（曾经在这里踩过：日志一切正常，但每个文件都返回 404 页面）。
    handler = functools.partial(Handler, directory=ROOT)
    srv = ThreadingHTTPServer(("0.0.0.0", port), handler)
    print("\n=== 服务已启动 http://0.0.0.0:%d  (根目录 %s) ===" % (port, ROOT))
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
