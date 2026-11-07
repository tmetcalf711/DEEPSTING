extends CanvasLayer
## Curse of the Cave-in: everything outside a small light radius around the wasp goes dark.
## Drawn above the world and below the HUD. Resolution independent (works in screen UV space).

const SHADER := """
shader_type canvas_item;
uniform vec2 center_uv = vec2(0.5);
uniform float aspect = 1.7778;
uniform float radius = 0.16;
uniform float soft = 0.08;
void fragment() {
	vec2 d = (SCREEN_UV - center_uv) * vec2(aspect, 1.0);
	float a = smoothstep(radius, radius + soft, length(d));
	COLOR = vec4(0.0, 0.0, 0.0, a * 0.94);
}
"""

var enabled_now := false
var _rect: ColorRect
var _mat: ShaderMaterial
var _radius_px := 56.0


func _ready() -> void:
	layer = 5
	_rect = ColorRect.new()
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = SHADER
	_mat = ShaderMaterial.new()
	_mat.shader = sh
	_rect.material = _mat
	add_child(_rect)
	visible = false


## radius is in world pixels (the camera zooms 2x, so it doubles on the 640x360 canvas).
func set_enabled(on: bool, radius_world_px: float = 56.0) -> void:
	enabled_now = on
	visible = on
	_radius_px = radius_world_px


## screen_pos: the light center in canvas (viewport) coordinates.
func track(screen_pos: Vector2, viewport_size: Vector2) -> void:
	if not enabled_now:
		return
	var zoom := 2.0
	_mat.set_shader_parameter("center_uv", screen_pos / viewport_size)
	_mat.set_shader_parameter("aspect", viewport_size.x / viewport_size.y)
	_mat.set_shader_parameter("radius", _radius_px * zoom / viewport_size.y)
	_mat.set_shader_parameter("soft", 24.0 * zoom / viewport_size.y)
