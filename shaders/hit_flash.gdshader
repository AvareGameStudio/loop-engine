shader_type canvas_item;
render_mode unshaded;

uniform vec4 flash_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float amount : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	// COLOR already carries vertex color * modulate for draw_* primitives.
	COLOR = vec4(mix(COLOR.rgb, flash_color.rgb, amount), COLOR.a);
}
