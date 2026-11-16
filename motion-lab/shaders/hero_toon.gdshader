shader_type spatial;
render_mode unshaded, cull_back, depth_draw_opaque;
uniform vec4 base_color : source_color = vec4(0.7, 0.7, 0.7, 1.0);
uniform float hit_flash : hint_range(0.0,1.0) = 0.0;
uniform float charge_glow : hint_range(0.0,1.0) = 0.0;
void fragment() {
 vec3 world_normal = normalize(mat3(INV_VIEW_MATRIX) * NORMAL);
 float light = dot(world_normal, normalize(vec3(-0.45,0.80,0.65)));
 // Soft thresholds preserve the clean palette without flickering, harsh
 // quantization across the low-poly character's small face and hands.
 float band = 0.64 + 0.25 * smoothstep(-0.22,-0.02,light)
                   + 0.20 * smoothstep(0.40,0.64,light);
 vec3 col = base_color.rgb * band;
 col = mix(col, vec3(1.0,0.92,0.69), hit_flash);
 col += charge_glow * vec3(0.055,0.037,0.014);
 ALBEDO = col;
}
