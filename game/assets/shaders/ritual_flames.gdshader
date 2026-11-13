shader_type canvas_item;
render_mode unshaded;

uniform float coverage : hint_range(0.0, 1.0) = 0.0;
uniform float full_screen : hint_range(0.0, 1.0) = 1.0;
// Ratio reel de la surface rendue. Le domaine procedural est exprime en
// unites de hauteur : une flamme conserve ses proportions sur tout ecran.
uniform float render_aspect : hint_range(0.2, 4.0) = 0.5625;

vec2 hash22(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
	p3 += dot(p3, p3.yzx + 33.33);
	return -1.0 + 2.0 * fract((p3.xx + p3.yz) * p3.zy);
}

float hash21(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

// Bruit de gradient avec interpolation quintique. Les cellules de calcul ne
// peuvent pas apparaitre sous forme de grands carres sur un ecran tres haut.
float gradient_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
	float value = mix(
		mix(dot(hash22(i), f),
			dot(hash22(i + vec2(1.0, 0.0)), f - vec2(1.0, 0.0)), u.x),
		mix(dot(hash22(i + vec2(0.0, 1.0)), f - vec2(0.0, 1.0)),
			dot(hash22(i + vec2(1.0)), f - vec2(1.0)), u.x),
		u.y);
	return clamp(value * 0.72 + 0.5, 0.0, 1.0);
}

float fbm(vec2 p) {
	float value = 0.0;
	float amplitude = 0.55;
	mat2 rotation = mat2(vec2(0.80, 0.60), vec2(-0.60, 0.80));
	for (int i = 0; i < 4; i++) {
		value += gradient_noise(p) * amplitude;
		// La rotation empeche les octaves de reveler une grille commune.
		p = rotation * p * 2.03 + vec2(17.1, 9.2);
		amplitude *= 0.48;
	}
	return value;
}

void fragment() {
	vec2 uv = UV;
	float upward = 1.0 - uv.y;
	vec2 flame_space = vec2((uv.x - 0.5) * render_aspect, upward);
	float maximum_height = mix(0.25, 1.12, full_screen);
	float active_height = maximum_height * coverage;
	float time = TIME;
	// Les transitions basses ne paient aucun calcul sur le reste de l'ecran.
	if (full_screen < 0.5 && upward > active_height + 0.19) {
		discard;
	}

	// Le domaine est deforme avant le FBM. Le mouvement reste organique et ne
	// depend ni de la largeur en pixels ni du format du telephone.
	vec2 broad_domain = vec2(flame_space.x * 13.0,
		flame_space.y * 3.1 - time * 1.16);
	vec2 warp = vec2(
		gradient_noise(broad_domain * 0.72 + vec2(7.4, time * 0.21)),
		gradient_noise(broad_domain * 0.72 + vec2(19.1, -time * 0.17))) - 0.5;
	float broad = fbm(broad_domain + warp * 1.15);
	float detail = gradient_noise(vec2(flame_space.x * 31.0 + broad * 1.7,
		flame_space.y * 8.2 - time * 2.45));
	float tongues = broad * 0.31 + detail * 0.12;
	float boundary = active_height * (0.69 + tongues);
	float edge_softness = max(fwidth(upward) * 2.0, 0.0045);
	float body = 1.0 - smoothstep(boundary - edge_softness * 2.0,
		boundary + edge_softness, upward);

	float relative_height = clamp(upward / max(boundary, 0.001), 0.0, 1.0);
	float inner_noise = gradient_noise(vec2(
		flame_space.x * 24.0 - time * 0.37,
		flame_space.y * 9.0 - time * 2.8) + warp * 0.85);
	float hot_core = smoothstep(0.62, 0.93,
		inner_noise + (1.0 - relative_height) * 0.54);
	float middle = smoothstep(0.16, 0.82,
		1.0 - relative_height + inner_noise * 0.19);

	vec3 coal = vec3(0.105, 0.004, 0.002);
	vec3 blood = vec3(0.58, 0.012, 0.004);
	vec3 orange = vec3(1.0, 0.19, 0.008);
	vec3 sulfur = vec3(1.0, 0.69, 0.11);
	vec3 fire = mix(coal, blood, middle);
	fire = mix(fire, orange, smoothstep(0.32, 0.82, middle));
	fire = mix(fire, sulfur, hot_core * (1.0 - relative_height * 0.62));

	// Au premier embrasement, une fumee rouge-noir ferme les interstices.
	float smoke = full_screen * coverage * smoothstep(0.48, 1.0, coverage);
	vec3 smoke_color = vec3(0.055, 0.002, 0.001)
		+ broad * vec3(0.10, 0.006, 0.002);
	float smoke_alpha = smoke * (0.78 + broad * 0.18);

	// Les braises sont des points circulaires ; leur grille reste invisible.
	vec2 ember_domain = vec2(flame_space.x * 76.0,
		(flame_space.y + time * 0.17) * 42.0);
	vec2 ember_cell = floor(ember_domain);
	vec2 ember_uv = fract(ember_domain) - 0.5;
	float ember_seed = hash21(ember_cell);
	float ember = step(0.94, ember_seed)
		* smoothstep(0.15, 0.02, length(ember_uv));
	ember *= step(upward, active_height + 0.18) * coverage;

	vec3 final_color = mix(smoke_color, fire, body);
	float alpha = max(smoke_alpha, body * coverage);
	final_color = mix(final_color, sulfur, ember);
	alpha = max(alpha, ember * 0.92);
	COLOR = vec4(final_color, alpha);
}
