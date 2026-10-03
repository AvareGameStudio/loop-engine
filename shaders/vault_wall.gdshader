shader_type canvas_item;
render_mode unshaded;

uniform vec4 plate : source_color = vec4(0.055, 0.06, 0.075, 1.0);
uniform vec4 sheen : source_color = vec4(0.16, 0.17, 0.2, 1.0);
uniform vec4 rivet_color : source_color = vec4(0.42, 0.44, 0.48, 1.0);

void fragment() {
	vec2 cell = fract(UV * vec2(5.0, 9.0));
	float seam = smoothstep(0.0, 0.015, cell.x) * smoothstep(0.0, 0.015, cell.y);
	seam *= smoothstep(1.0, 0.985, cell.x) * smoothstep(1.0, 0.985, cell.y);
	float brush = 0.85 + 0.15 * sin(UV.y * 90.0);
	float rivet = smoothstep(0.045, 0.012, distance(cell, vec2(0.06, 0.06)));
	rivet += smoothstep(0.045, 0.012, distance(cell, vec2(0.94, 0.06)));
	rivet += smoothstep(0.045, 0.012, distance(cell, vec2(0.06, 0.94)));
	rivet += smoothstep(0.045, 0.012, distance(cell, vec2(0.94, 0.94)));
	float lamp = smoothstep(0.15, 0.0, distance(UV, vec2(0.5, 0.38)));
	vec3 col = mix(plate.rgb, sheen.rgb, lamp * 0.55) * brush;
	col = mix(col * 0.45, col, seam);
	col = mix(col, rivet_color.rgb, clamp(rivet, 0.0, 1.0));
	COLOR = vec4(col, 1.0);
}
