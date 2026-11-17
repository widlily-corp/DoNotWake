shader_type canvas_item;

uniform float scanline_count : hint_range(100.0, 720.0) = 360.0;
uniform float scanline_intensity : hint_range(0.0, 1.0) = 0.22;
uniform float vignette_intensity : hint_range(0.0, 1.0) = 0.35;
uniform float curvature : hint_range(0.0, 0.1) = 0.02;
uniform vec4 phosphor_tint : source_color = vec4(0.92, 0.98, 0.96, 1.0);
uniform sampler2D screen_texture : hint_screen_texture, filter_nearest;

vec2 curve(vec2 uv) {
	vec2 delta = uv - 0.5;
	float dist_sq = dot(delta, delta);
	return uv + delta * dist_sq * curvature;
}

void fragment() {
	vec2 curved_uv = curve(SCREEN_UV);

	if (curved_uv.x < 0.0 || curved_uv.x > 1.0 || curved_uv.y < 0.0 || curved_uv.y > 1.0) {
		COLOR = vec4(0.0, 0.0, 0.0, 1.0);
	} else {
		vec4 col = texture(screen_texture, curved_uv) * phosphor_tint;

		// Scanlines
		float scanline = sin(curved_uv.y * scanline_count * 3.14159 * 2.0);
		col.rgb *= 1.0 - (scanline_intensity * (0.5 + 0.5 * scanline));

		// Vignette
		vec2 vig_uv = curved_uv * (1.0 - curved_uv.yx);
		float vig = vig_uv.x * vig_uv.y * 15.0;
		vig = clamp(pow(vig, vignette_intensity), 0.0, 1.0);
		col.rgb *= vig;

		COLOR = col;
	}
}
