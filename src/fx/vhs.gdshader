// SAFE MODE — full-screen VHS / CRT / analog-horror post process.
// Applied to a ColorRect (full rect) on a CanvasLayer above the 3D view.
// Drives the subtle-liminal look: soft grain, scanlines, chroma bleed,
// vignette, and a "corruption" term the Horror director pushes toward 1.0
// when the malware is near or during scripted dread beats.
shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;

uniform float time_s = 0.0;              // fed from GDScript (Date-free)
uniform float grain_amount : hint_range(0.0, 1.0) = 0.06;
uniform float scanline_amount : hint_range(0.0, 1.0) = 0.10;
uniform float aberration : hint_range(0.0, 0.02) = 0.0015;
uniform float vignette_amount : hint_range(0.0, 1.5) = 0.55;
uniform float corruption : hint_range(0.0, 1.0) = 0.0; // 0 = calm, 1 = wrong
uniform float desaturate : hint_range(0.0, 1.0) = 0.25;

// cheap hash noise
float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

void fragment() {
	vec2 uv = SCREEN_UV;

	// vertical roll / jitter grows with corruption
	float roll = sin((uv.y * 40.0) + time_s * 6.0) * 0.0012 * corruption;
	float tear = step(0.995 - corruption * 0.06, hash(vec2(floor(uv.y * 90.0), floor(time_s * 12.0))));
	uv.x += roll + tear * 0.03 * corruption;

	// chromatic aberration, stronger near edges and with corruption
	float edge = distance(uv, vec2(0.5));
	float ca = aberration + corruption * 0.006 + edge * 0.002;
	vec3 col;
	col.r = texture(screen_tex, uv + vec2(ca, 0.0)).r;
	col.g = texture(screen_tex, uv).g;
	col.b = texture(screen_tex, uv - vec2(ca, 0.0)).b;

	// desaturate toward a sick greenish gray as things go wrong
	float lum = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(col, vec3(lum) * vec3(0.9, 1.03, 0.95), desaturate + corruption * 0.35);

	// scanlines
	float sl = sin(uv.y * (720.0)) * 0.5 + 0.5;
	col *= 1.0 - scanline_amount * (1.0 - sl);

	// animated grain
	float g = hash(uv * vec2(1920.0, 1080.0) + time_s * 60.0);
	col += (g - 0.5) * (grain_amount + corruption * 0.08);

	// vignette
	float vig = smoothstep(0.9, 0.35, edge);
	col *= mix(1.0, vig, vignette_amount);

	// rare full-frame signal drop when corruption is high
	float drop = step(0.9985 - corruption * 0.02, hash(vec2(floor(time_s * 8.0), 7.0)));
	col = mix(col, vec3(hash(uv + time_s)) * 0.15, drop * corruption);

	COLOR = vec4(col, 1.0);
}
