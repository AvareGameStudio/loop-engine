shader_type canvas_item;
render_mode unshaded, blend_add;

uniform vec4 glow_color : source_color = vec4(0.2, 0.9, 0.4, 1.0);
uniform float pulse : hint_range(0.0, 6.28) = 0.0;
uniform float intensity : hint_range(0.0, 3.0) = 1.0;
uniform float ripple : hint_range(0.0, 1.5) = 0.0;
uniform vec2 origin = vec2(360.0, 580.0);
uniform vec2 rect_size = vec2(720.0, 1280.0);
uniform float reach = 1100.0;

void fragment() {
	// UV is top-left of this fullscreen rect, so the origin stays on the vault hub.
	vec2 px = UV * rect_size;
	float d = distance(px, origin) / reach;
	float breath = 0.65 + 0.35 * sin(pulse);
	float wave = 0.0;
	if (ripple > 0.02) {
		wave = smoothstep(ripple - 0.06, ripple, d) * (1.0 - smoothstep(ripple, ripple + 0.04, d));
	}
	COLOR = glow_color * wave * breath * intensity;
}
