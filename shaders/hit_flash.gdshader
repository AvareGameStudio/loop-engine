shader_type canvas_item;
render_mode unshaded, blend_add;

uniform vec4 flash_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float amount : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec4 base = texture(TEXTURE, UV);
	COLOR = mix(base, flash_color, amount);
	COLOR.a *= base.a;
}
