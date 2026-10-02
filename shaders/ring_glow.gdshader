shader_type canvas_item;
render_mode unshaded, blend_add;

uniform vec4 glow_color : source_color = vec4(0.2, 0.9, 1.0, 1.0);
uniform float pulse : hint_range(0.0, 6.28) = 0.0;
uniform float intensity : hint_range(0.0, 3.0) = 1.0;

void fragment() {
	float d = distance(UV, vec2(0.5));
	float ring = smoothstep(0.48, 0.42, d) * smoothstep(0.32, 0.38, d);
	float breath = 0.65 + 0.35 * sin(pulse);
	COLOR = glow_color * ring * breath * intensity;
}
