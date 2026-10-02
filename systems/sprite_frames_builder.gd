class_name SpriteFramesBuilder
extends RefCounted


## 由「动画名 → {dir, fps, loop}」字典运行时构建 SpriteFrames（帧文件夹内按文件名排序）。
static func build(anim_dirs: Dictionary) -> SpriteFrames:
	var frames := SpriteFrames.new()
	for anim_name in anim_dirs:
		if not anim_dirs[anim_name] is Dictionary:
			push_warning("SpriteFramesBuilder: config for \"%s\" is not a Dictionary." % anim_name)
			continue
		var config: Dictionary = anim_dirs[anim_name]
		var dir_path: String = String(config.get("dir", ""))
		var fps: float = float(config.get("fps", 8))
		var loop: bool = bool(config.get("loop", true))
		var anim := StringName(anim_name)
		var frame_paths := _list_pngs(dir_path)
		if frame_paths.is_empty():
			# 目录不存在/没有 PNG：跳过该动画，不要留一个 0 帧动画进 SpriteFrames
			push_warning("SpriteFramesBuilder: no PNG found in \"%s\" for animation \"%s\" (animation skipped)." % [dir_path, anim_name])
			continue
		if not frames.has_animation(anim):
			frames.add_animation(anim)
		frames.set_animation_speed(anim, fps)
		frames.set_animation_loop(anim, loop)
		for path in frame_paths:
			var texture := load(path) as Texture2D
			if texture != null:
				frames.add_frame(anim, texture)
			else:
				push_warning("SpriteFramesBuilder: failed to load \"%s\"." % path)
	if frames.has_animation(&"default"):
		frames.remove_animation(&"default")
	return frames


static func _list_pngs(dir_path: String) -> PackedStringArray:
	var paths := PackedStringArray()
	if dir_path.is_empty():
		return paths
	var dir := DirAccess.open(dir_path)
	if dir == null:
		push_warning("SpriteFramesBuilder: cannot open directory \"%s\"." % dir_path)
		return paths
	for file_name in dir.get_files():
		if file_name.get_extension().to_lower() == "png":
			paths.append(dir_path.path_join(file_name))
	paths.sort()
	return paths
