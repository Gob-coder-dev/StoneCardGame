shader_type canvas_item;
render_mode unshaded;

uniform float coverage : hint_range(0.0, 1.0) = 0.0;
uniform float full_screen : hint_range(0.0, 1.0) = 1.0;
// Corrige uniquement le domaine procédural. La progression verticale continue
// d'utiliser les UV normalisés afin de couvrir l'écran de bas en haut.
uniform float aspect_correction : hint_range(0.25, 4.0) = 1.0;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), f.x),
		mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0)), f.x), f.y);
}

float fbm(vec2 p) {
	float value = 0.0;
	float amplitude = 0.55;
	for (int i = 0; i < 4; i++) {
		value += noise(p) * amplitude;
		p = p * 2.03 + vec2(17.1, 9.2);
		amplitude *= 0.48;
	}
	return value;
}

void fragment() {
	vec2 uv = UV;
	float procedural_x = (uv.x - 0.5) * aspect_correction + 0.5;
	float upward = 1.0 - uv.y;
	float maximum_height = mix(0.25, 1.12, full_screen);
	float active_height = maximum_height * coverage;
	float time = TIME;
	// Les transitions basses ne paient aucun calcul de bruit sur le reste de
	// l'écran, ce qui garde l'effet léger sur les GPU mobiles.
	if (full_screen < 0.5 && upward > active_height + 0.19) {
		discard;
	}

	// Deux champs qui montent à des vitesses différentes cassent toute répétition
	// géométrique et forment des langues de feu mouvantes.
	float broad = fbm(vec2(procedural_x * 5.2, upward * 2.3 - time * 1.16));
	float detail = noise(vec2(procedural_x * 13.7 + 4.0,
		upward * 5.8 - time * 2.45));
	float tongues = broad * 0.31 + detail * 0.12;
	float boundary = active_height * (0.69 + tongues);
	float body = 1.0 - smoothstep(boundary - 0.035, boundary + 0.028, upward);

	float relative_height = clamp(upward / max(boundary, 0.001), 0.0, 1.0);
	float inner_noise = noise(vec2(procedural_x * 10.0 - time * 0.37,
		upward * 8.0 - time * 2.8));
	float hot_core = smoothstep(0.62, 0.93, inner_noise + (1.0 - relative_height) * 0.54);
	float middle = smoothstep(0.16, 0.82, 1.0 - relative_height + inner_noise * 0.19);

	vec3 coal = vec3(0.105, 0.004, 0.002);
	vec3 blood = vec3(0.58, 0.012, 0.004);
	vec3 orange = vec3(1.0, 0.19, 0.008);
	vec3 sulfur = vec3(1.0, 0.69, 0.11);
	vec3 fire = mix(coal, blood, middle);
	fire = mix(fire, orange, smoothstep(0.32, 0.82, middle));
	fire = mix(fire, sulfur, hot_core * (1.0 - relative_height * 0.62));

	// Au premier embrasement seulement, une fumée rouge-noir ferme également
	// les interstices au sommet afin que l'écran soit réellement englouti.
	float smoke = full_screen * coverage * smoothstep(0.48, 1.0, coverage);
	vec3 smoke_color = vec3(0.055, 0.002, 0.001) + broad * vec3(0.10, 0.006, 0.002);
	float smoke_alpha = smoke * (0.78 + broad * 0.18);

	// Quelques braises irrégulières se détachent au-dessus du front de flamme.
	vec2 ember_domain = vec2(procedural_x * 34.0,
		(upward + time * 0.17) * 38.0);
	vec2 ember_cell = floor(ember_domain);
	vec2 ember_uv = fract(ember_domain) - 0.5;
	float ember_seed = hash21(ember_cell);
	float ember = step(0.94, ember_seed) * smoothstep(0.15, 0.02, length(ember_uv));
	ember *= step(upward, active_height + 0.18) * coverage;

	vec3 final_color = mix(smoke_color, fire, body);
	float alpha = max(smoke_alpha, body * coverage);
	final_color = mix(final_color, sulfur, ember);
	alpha = max(alpha, ember * 0.92);
	COLOR = vec4(final_color, alpha);
}
