## Calcule la géométrie du tiroir d'actions dans le repère de sa couche.
## Ce composant ne modifie aucun Control : il centralise uniquement les règles
## de placement partagées par le deck et la collection.
class_name CardActionPlacement
extends RefCounted


static func resolve(layer: Control, wrapper: Control, card: StoneCard,
		use_collection_width: bool) -> Dictionary:
	if layer == null or wrapper == null or card == null:
		return {}
	var progress := wrapper.get_node_or_null("Progress") as Control
	var has_progress := progress != null and progress.visible
	var horizontal_anchor: Control = wrapper if use_collection_width else card
	if not use_collection_width and has_progress:
		horizontal_anchor = progress
	var horizontal_rect := control_rect_in(layer, horizontal_anchor)
	var bottom := control_rect_in(layer, progress).end.y if has_progress \
		else _card_visual_bottom_in(layer, card)
	return {
		"x": horizontal_rect.position.x,
		"width": horizontal_rect.size.x,
		"bottom": bottom,
	}


static func control_rect_in(layer: Control, control: Control) -> Rect2:
	if layer == null or control == null:
		return Rect2()
	var relative := layer.get_global_transform().affine_inverse() \
		* control.get_global_transform()
	return _transformed_rect(relative, Rect2(Vector2.ZERO, control.size))


static func _card_visual_bottom_in(layer: Control, card: StoneCard) -> float:
	var relative := layer.get_global_transform().affine_inverse() \
		* card.get_global_transform()
	var local_bottom := card.visual_content_bottom()
	var left := relative * Vector2(0.0, local_bottom)
	var right := relative * Vector2(card.size.x, local_bottom)
	return maxf(left.y, right.y)


static func _transformed_rect(transform: Transform2D, source: Rect2) -> Rect2:
	var points: Array[Vector2] = [
		transform * source.position,
		transform * Vector2(source.end.x, source.position.y),
		transform * Vector2(source.position.x, source.end.y),
		transform * source.end,
	]
	var minimum: Vector2 = points[0]
	var maximum: Vector2 = points[0]
	for point: Vector2 in points:
		minimum = Vector2(minf(minimum.x, point.x), minf(minimum.y, point.y))
		maximum = Vector2(maxf(maximum.x, point.x), maxf(maximum.y, point.y))
	return Rect2(minimum, maximum - minimum)
