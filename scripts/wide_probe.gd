extends SceneTree

# 宽屏横屏触发诊断探针：打印窗口/视口/布局真实状态
func _initialize() -> void:
	var st := root
	var ds := st.content_scale_size
	var vr := st.get_visible_rect()
	var w := DisplayServer.window_get_size()
	print("window_get_size   = %s" % str(w))
	print("content_scale_size= %s" % str(ds))
	print("visible_rect      = %s" % str(vr))
	var sm = st.get_node("ScreenMode")
	print("is_widescreen     = %s" % str(sm.is_widescreen()))
	print("should_landscape  = %s" % str(sm.should_landscape()))
	var d = st.get_node("Data")
	print("Data.is_landscape = %s" % str(d.is_landscape()))
	print("design_size       = %s" % str(st.get_node("HudLayout").design_size()))
	print("buttons_pivot     = %s" % str(st.get_node("HudLayout").buttons_pivot()))
	print("dash_center       = %s" % str(st.get_node("HudLayout").buttons_dash_center()))
	print("joy_fixed_base    = %s" % str(st.get_node("HudLayout").joy_fixed_base()))
	quit(0)
