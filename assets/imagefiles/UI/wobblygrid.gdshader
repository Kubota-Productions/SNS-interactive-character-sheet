shader_type canvas_item;

uniform vec3 color: source_color;
uniform float base_point_size : hint_range(0.0, 100.0, 0.1) = 20.0;
uniform vec2 size;
uniform sampler2D noise: filter_nearest;
uniform sampler2D noise2: filter_nearest;
uniform float edge_fade : hint_range(0.0, 1.0, 0.1);
uniform float wave_speed : hint_range(0.0, 10.0, 0.1);
uniform float softness : hint_range(0.001, 0.1, 0.001) = 0.02;
uniform float growth_strength : hint_range(0.0, 3.0, 0.01) = 1.0;
uniform float clump_strength : hint_range(0.0, 9.0, 0.01) = 0.5;
uniform float sway_strength : hint_range(0.0, 0.5, 0.01) = 0.1;
uniform float sway_speed : hint_range(0.1, 5.0, 0.1) = 1.0;

// Mouse interaction
uniform vec2 mouse_pos = vec2(0.5, 0.5); 
uniform float mouse_strength : hint_range(0.0, 8.0, 0.01) = 0.5; 
uniform float mouse_growth : hint_range(0.0, 10.0, 0.01) = 0.5;  
uniform float mouse_radius : hint_range(0.0, 1.0, 0.01) = 0.2; // range of effect

// Simple hash for randomness
float hash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
    // Noise modulation
    float n = texture(noise, mod(UV - TIME * wave_speed / 21.2, 1.0)).r;
    float n2 = texture(noise2, mod(UV + 14.7 + TIME * wave_speed / 40.3, 1.0)).r;
    float n3 = clamp(0.0, 0.3 + pow(n + (n2 * 0.4), 3.0) * 1.5, 1.0);
    COLOR.rgb = color + vec3(n3);

    vec2 m = 1.0 - (edge_fade * abs(UV - 0.5) * 2.0 * size - size + 1.0 + base_point_size / 50.0);
    float ma = min(m.x, m.y);

    // Grid coords
    vec2 gridPos = floor(UV * size);
    vec2 gridUV  = fract(UV * size);

    // Base dot radius (noise-driven)
    float radius = (base_point_size / 100.0) * (1.0 + (n3 - 0.5) * 2.0 * growth_strength);
    radius = max(radius, 0.001);

    // Base center
    vec2 cellCenter = vec2(0.5, 0.5);

    // Clumping
    float clump_amount = (1.0 - n3) * clump_strength;
    vec2 noise_offset = (texture(noise2, UV * size * 0.5 + TIME * 0.05).rg - 0.5) * 2.0;
    vec2 clumpedUV = mix(gridUV, gridUV + noise_offset * 0.3, clump_amount);

    // Sway
    float randX = hash(gridPos + vec2(13.1, 7.7));
    float randY = hash(gridPos + vec2(91.5, 27.3));
    vec2 sway = vec2(
        sin(TIME * sway_speed + randX * 6.2831),
        cos(TIME * sway_speed + randY * 6.2831)
    ) * sway_strength;

    // Mouse attraction (localized, smooth)
    vec2 cellUV = (gridPos + cellCenter) / size;
    vec2 to_mouse = mouse_pos - cellUV;
    float dist_to_mouse = length(to_mouse);

    // Smooth falloff using smoothstep
    float falloff = 1.0 - smoothstep(0.0, mouse_radius, dist_to_mouse);

    // Apply movement and growth
    clumpedUV += to_mouse * mouse_strength * falloff;
    float adjusted_radius = radius * (1.0 + mouse_growth * falloff);

    // Apply sway
    vec2 shiftedUV = clumpedUV + sway;

    // Distance from cell center
    float dist = length(shiftedUV - cellCenter);

    // Smooth circle
    float circle = 1.0 - smoothstep(adjusted_radius - softness, adjusted_radius + softness, dist);

    // Final alpha
    COLOR.a = ma * n3 * circle;
}
