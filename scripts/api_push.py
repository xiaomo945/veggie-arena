#!/usr/bin/env python3
"""github.com 被沙箱代理 502 时，用 GitHub REST API 推送本地已提交的 commit。

Git 是内容寻址：blob / tree / commit 的 sha 只取决于内容。
按与本地提交完全相同的父提交、树、author/committer/message 重建，
得到的 commit sha 与本地一致（若 GitHub 归一化有偏差则接受新 sha，
并把本地 ref 对齐到远端，保证本地 = 远端）。

踩过的坑（2026-10，第一次用就栽了）：
   每个 tree entry 的 mode 必须从 `git ls-tree` 读真值，不能硬编码 100644 ——
   本仓库 scripts/check.sh 是 100755，硬编码后树 sha 与本地对不上，
   表现为"515 个 blob 内容全一致，树 sha 却不同"，极难定位。

用法：GH_TOKEN=<pat> python api_push.py <parent-sha> <target-sha> <branch> [--force]
  --force  允许非快进更新（仅用于把推错的远端 HEAD 修回正确提交）
"""
import base64
import datetime
import json
import os
import subprocess
import sys
import urllib.request

REPO = "xiaomo945/veggie-arena"
API = "https://api.github.com"


def sh(*args: str) -> str:
    # ⚠️ text=True 默认按 Windows 本地编码（GBK）解码，git 输出的是 UTF-8，
    # 中文路径会乱码 —— 后续与 -z 的原始字节路径互相匹配时静默错位。
    # 显式 utf-8（踩过：docs/07_积压需求与排期.md 推送时 KeyError）。
    return subprocess.check_output(args, text=True, encoding="utf-8").strip()


def gh(method: str, path: str, payload=None):
    token = os.environ["GH_TOKEN"]
    data = json.dumps(payload).encode("utf-8") if payload is not None else None
    req = urllib.request.Request(
        API + path,
        method=method,
        data=data,
        headers={
            "Authorization": "Bearer " + token,
            "Accept": "application/vnd.github+json",
            "X-GitHub-Api-Version": "2022-11-28",
            "Content-Type": "application/json",
        },
    )
    with urllib.request.urlopen(req, timeout=60) as r:
        return json.loads(r.read().decode("utf-8"))


def parse_ident(s: str) -> dict:
    name = s[: s.rindex(" <")]
    email = s[s.rindex(" <") + 2 : s.rindex(">")]
    ts, tz = s[s.rindex(">") + 2 :].split()
    sign = 1 if tz[0] == "+" else -1
    off = datetime.timedelta(hours=int(tz[1:3]), minutes=int(tz[3:5])) * sign
    dt = datetime.datetime.fromtimestamp(int(ts), datetime.timezone(off))
    return {"name": name, "email": email, "date": dt.isoformat()}


def changed_files(parent: str, target: str) -> list:
    """相对父提交的变更清单。用 -z 拿原始字节路径，规避中文路径转义与制表符误切。"""
    raw = sh("git", "diff", "--name-status", "-z", parent, target)
    parts = raw.split("\0")
    out = []
    i = 0
    while i + 1 < len(parts) and parts[i] != "":  # -z 输出末尾带一个 NUL，split 会多个空尾
        st, p = parts[i], parts[i + 1]
        if st[0] in "RC":                      # rename/copy：st 形如 R100，后跟两个路径
            out.append((st, p, parts[i + 2]))
            i += 3
        else:
            out.append((st, p, None))
            i += 2
    return out


def main() -> None:
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    force = "--force" in sys.argv[1:]
    parent, target, branch = args
    # 全部归一成全 sha：传短 sha 进来时，末尾的 match 比对会假阴性，误导排查方向
    parent = sh("git", "rev-parse", parent)
    target = sh("git", "rev-parse", target)

    # 1. 变更文件清单（相对父提交）
    files = changed_files(parent, target)
    print("changed files: %d" % len(files))

    # 2. 每个路径的真实 git mode（100644/100755/120000/160000）——从 ls-tree 读，别猜。
    #    ⚠️ 必须 -z：git 对非 ASCII 路径会加双引号并转义（"docs/07\351..."），
    #    与 diff -z 的原始路径对不上（KeyError 就是这么来的）。
    modes: dict = {}
    for ln in sh("git", "ls-tree", "-r", "-z", target).split("\0"):
        if not ln:
            continue
        meta, path = ln.split("\t", 1)
        mode, typ, sha = meta.split()
        modes[path] = (mode, typ, sha)

    # 3. 逐文件建 blob（内容取 git 对象库，和磁盘/换行符无关）
    entries = []
    for st, p_old, p_new in files:
        if st.startswith("D"):
            entries.append({"path": p_old, "mode": "100644", "type": "blob", "sha": None})
            continue
        path = p_new if p_new else p_old
        mode, typ, _sha = modes[path]
        if typ != "blob":                      # submodule 等，本仓库用不到，直接带真相交
            entries.append({"path": path, "mode": mode, "type": typ, "sha": _sha})
        else:
            content = subprocess.check_output(["git", "cat-file", "blob", "%s:%s" % (target, path)])
            b = gh("POST", "/repos/%s/git/blobs" % REPO,
                   {"content": base64.b64encode(content).decode("ascii"), "encoding": "base64"})
            entries.append({"path": path, "mode": mode, "type": "blob", "sha": b["sha"]})
        if p_new:                              # rename/copy 的旧路径要删掉
            entries.append({"path": p_old, "mode": "100644", "type": "blob", "sha": None})
    print("  tree entries: %d" % len(entries))

    # 4. 建树（base_tree = 父提交的树，只动变更路径）
    parent_tree = sh("git", "rev-parse", "%s^{tree}" % parent)
    t = gh("POST", "/repos/%s/git/trees" % REPO, {"base_tree": parent_tree, "tree": entries})
    local_tree = sh("git", "rev-parse", "%s^{tree}" % target)
    print("tree api=%s local=%s match=%s" % (t["sha"], local_tree, t["sha"] == local_tree))

    # 5. 复刻 author/committer/message 建 commit
    # ⚠️ cat-file 的输出必须原样读，不能过 sh() —— sh() 的 .strip() 会把 message
    # 尾部的 \n 删掉，GitHub 侧是原样存储的，于是重建出的 commit 对象与本地
    # 差一个字节，sha 必然对不上（实测：strip 后得 736bd120，原样得 4cca169）。
    raw = subprocess.check_output(["git", "cat-file", "commit", target], text=True)
    body = raw.split("\n\n", 1)[1]
    a = parse_ident([l for l in raw.split("\n") if l.startswith("author ")][0][7:])
    c = parse_ident([l for l in raw.split("\n") if l.startswith("committer ")][0][10:])
    cm = gh("POST", "/repos/%s/git/commits" % REPO,
            {"message": body, "tree": t["sha"], "parents": [parent], "author": a, "committer": c})
    print("commit api=%s local=%s match=%s" % (cm["sha"], target, cm["sha"] == target))

    # 6. 更新分支引用
    r = gh("PATCH", "/repos/%s/git/refs/heads/%s" % (REPO, branch),
           {"sha": cm["sha"], "force": force})
    print("ref %s -> %s (force=%s)" % (branch, r["object"]["sha"], force))
    print("API_PUSH_SHA %s" % cm["sha"])


if __name__ == "__main__":
    main()
