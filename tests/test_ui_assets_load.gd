extends SceneTree

const ASSETS := {
	"res://assets/sprites/ui/diag_frame.png": Vector2i(960, 420),
	"res://assets/sprites/ui/doc_reader_bg.png": Vector2i(920, 560),
	"res://assets/sprites/ui/card_tab.png": Vector2i(48, 24),
	"res://assets/sprites/ui/glitch_strip.png": Vector2i(256, 16),
	"res://assets/sprites/ui/doc_folder.png": Vector2i(64, 64),
	"res://assets/sprites/ui/diag_needle.png": Vector2i(32, 64),
	"res://docs/keyart.png": Vector2i(1280, 720),
}

func _init() -> void:
	print("--- TEST UI ASSETS LOAD IN GODOT ENGINE ---")
	var failed := 0
	var passed := 0

	for res_path in ASSETS.keys():
		var expected_size: Vector2i = ASSETS[res_path]
		var global_path := ProjectSettings.globalize_path(res_path)
		
		# 1. Test Image.load_from_file
		var img := Image.new()
		var err := img.load(global_path)
		if err != OK:
			print("  [FAIL] Failed to load Image from file: %s (Error code: %d)" % [res_path, err])
			failed += 1
			continue
		
		var actual_size := img.get_size()
		if actual_size != expected_size:
			print("  [FAIL] Size mismatch for %s: expected %s, got %s" % [res_path, str(expected_size), str(actual_size)])
			failed += 1
			continue
		
		# 2. Test ImageTexture creation
		var tex := ImageTexture.create_from_image(img)
		if tex == null:
			print("  [FAIL] ImageTexture.create_from_image returned null for %s" % res_path)
			failed += 1
			continue
		
		print("  [OK] %s: loaded successfully as ImageTexture (size: %s)" % [res_path, str(actual_size)])
		passed += 1

	if failed > 0:
		print("--- UI ASSETS LOAD TEST FAILED: %d errors, %d passed ---" % [failed, passed])
		quit(1)
	else:
		print("--- ALL UI ASSETS LOADED SUCCESSFULLY: %d textures verified ---" % passed)
		quit(0)
