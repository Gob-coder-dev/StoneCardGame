extends Node


func _ready() -> void:
	StoryService.auto_start_tutorials = false
	for size in [Vector2i(1920, 1080), Vector2i(1280, 720), Vector2i(800, 600)]:
		get_window().size = size
		await get_tree().process_frame
		var page: Control = (load("res://scenes/menus/CollectionScreen.tscn") as PackedScene).instantiate()
		add_child(page)
		for frame in range(10):
			await get_tree().process_frame
		var sheet: Control = page.get_node("StoneInfoSheet")
		for stone in StoneLoader.get_all_stones():
			print("SIZE ", size, " OPEN ", stone["id"])
			sheet.open_for(str(stone["id"]))
			for frame in range(2):
				await get_tree().process_frame
		page.queue_free()
		await get_tree().process_frame
	print("FIN OK")
	get_tree().quit()
