shader_type canvas_item;

// Position du joueur en coordonnées écran normalisées (0-1)
uniform vec2  player_screen_pos = vec2(0.5, 0.5);

// Rayon de lumière (fraction de la hauteur d'écran)
uniform float light_radius = 0.22;

// Lumière ambiante très faible — permet de deviner des formes dans l'obscurité
uniform float ambient = 0.025;

void fragment() {
	vec2 uv = SCREEN_UV;

	// Correction d'aspect pour un cercle parfait
	float aspect = 1.0 / (SCREEN_PIXEL_SIZE.x / SCREEN_PIXEL_SIZE.y);
	vec2  diff   = uv - player_screen_pos;
	diff.x      *= aspect;

	float dist     = length(diff);
	float t        = clamp(dist / light_radius, 0.0, 1.0);

	// Falloff : doux au centre, très sombre au bord
	float darkness = t * t * t * t;

	float alpha = mix(ambient, 0.98, darkness);
	COLOR = vec4(0.0, 0.0, 0.0, alpha);
}
