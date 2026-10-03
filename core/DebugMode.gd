extends RefCounted

# 调试模式判定：只管"跳到第 N 波"这类测试入口的显隐。
#
# 为什么单独抽一个文件：用户明确要求 ——
#   "正式版的时候把这些测试按钮隐藏或者删除掉，只有一个测试游戏的模式才能直接到达某一步"
# 所以判定必须收敛在一处，别让 UI 里散落一堆 OS.is_debug_build()。
#
# 打开方式（满足其一即视为测试模式）：
#   1) debug 构建（编辑器里 F5 / 桌面 debug 导出）—— 开发日常；
#   2) Web 端 URL 带 ?debug=1 —— 发试玩链接时自己加参数，正式传播链接不带；
#   3) 命令行带 --debug-wave（配合 run_sim / 本地起服自测）。
# 正式 release 且无参数 → 一律关，按钮节点整个不创建，玩家永远看不到。

static func enabled() -> bool:
	if OS.is_debug_build():
		return true
	if OS.get_cmdline_user_args().has("--debug-wave"):
		return true
	if OS.has_feature("web"):
		var q := str(JavaScriptBridge.eval("window.location.search || ''", true))
		if q.contains("debug=1"):
			return true
	return false
