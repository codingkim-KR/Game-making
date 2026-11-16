shader_type spatial;
render_mode unshaded, cull_back, depth_draw_opaque;
// Capture-only variant of hero_toon.gdshader for pixel-art sprite renders.
// Same light direction and the same three brightness levels, but the band
// edges are hard steps. A soft smoothstep edge spreads one boundary over
// several pixels at sprite scale, which is exactly the "blurry outline" we
// are trying to remove; a hard edge lands on a single pixel row.
uniform vec4 base_color : source_color = vec4(0.7, 0.7, 0.7, 1.0);
uniform float shadow_level = 0.64;
uniform float mid_level = 0.89;
uniform float light_level = 1.09;
uniform float shadow_edge = -0.12;
uniform float light_edge = 0.52;
void fragment() {
 vec3 world_normal = normalize(mat3(INV_VIEW_MATRIX) * NORMAL);
 float light = dot(world_normal, normalize(vec3(-0.45,0.80,0.65)));
 float band = light < shadow_edge ? shadow_level : (light < light_edge ? mid_level : light_level);
 ALBEDO = base_color.rgb * band;
}
