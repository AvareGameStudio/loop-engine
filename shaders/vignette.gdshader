shader_type canvas_item;
render_mode unshaded;

uniform float strength : hint_range(0.0, 1.0) = 0.0;
uniform vec4 tint : source_color = vec4(0.55, 0.08, 0.1, 1.0);

void fragment() {
	float d = distance(UV, vec2(0.5));
	float edge = smoothstep(0.22, 0.78, d);
	float blur = smoothstep(0.35, 0.62, d) * (1.0 - smoothstep(0.62, 0.9, d));
	COLOR = vec4(tint.rgb, (edge * 0.9 + blur * 0.35) * strength);
}
