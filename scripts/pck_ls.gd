extends SceneTree

# 用 Godot 自己的 ProjectSettings.load_resource_pack 打开 pck，然后列目录。
# 别手写 pck 二进制解析：Godot 4.3 的目录项布局（md5/offset/size 字段顺序、
# REL_FILEBASE 时的相对基准）试了两版都解出垃圾值，而这里一行就拿到权威答案。
#
# 用法：godot --headless --script res://scripts/pck_ls.gd -- /abs/path/index.pck 前缀...

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		print("用法: -- <pck 路径> [前缀过滤...]")
		quit(1)
		return
	var path := args[0]
	if not ProjectSettings.load_resource_pack(path):
		print("❌ 打开失败: " + path)
		quit(1)
		return
	var filters: Array = []
	for i in range(1, args.size()):
		filters.append(args[i])

	var all: Array = DirAccess.get_files_at("res://")
	var dirs: Array = DirAccess.get_directories_at("res://")
	# get_files_at 不递归，手动走一层层目录（包内目录层级不深，够用）
	var stack: Array = ["res://"]
	var files: Array = []
	while not stack.is_empty():
		var cur: String = stack.pop_back()
		for f in DirAccess.get_files_at(cur):
			files.append(cur + f)
		for d in DirAccess.get_directories_at(cur):
			stack.append(cur + d + "/")

	var hit: Array = []
	for f in files:
		if filters.is_empty():
			hit.append(f)
			continue
		for pre in filters:
			if (f as String).begins_with(pre):
				hit.append(f)
				break
	hit.sort()
	print("包内文件总数 %d，命中过滤 %d" % [files.size(), hit.size()])
	for f in hit:
		print("  " + f)
	quit(0)
