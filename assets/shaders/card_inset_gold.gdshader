shader_type canvas_item;
render_mode unshaded;

uniform float strength = 0.0;
uniform float source_pixels_per_unit = 5.28;
uniform sampler2D title_paper : filter_linear;
uniform sampler2D gold_noise : filter_linear_mipmap, repeat_enable;
uniform float shimmer_clock = 0.0;
uniform float emission_strength = 0.11;
uniform vec2 source_origin = vec2(68.0,96.0);
uniform vec2 source_size = vec2(880.0,1372.0);
uniform bool cutout_title = true;

void fragment() {
	vec4 paper = texture(TEXTURE, UV);
	vec2 card_uv = (UV/TEXTURE_PIXEL_SIZE-source_origin)/source_size;
	float broad_wear = texture(gold_noise,card_uv*vec2(0.72,1.08)+vec2(0.19,0.43)).r;
	float medium_wear = texture(gold_noise,card_uv*vec2(1.65,2.35)+vec2(0.61,0.08)).r;
	float edge_wear = clamp(broad_wear*0.72+medium_wear*0.28,0.0,1.0);
	float corner = smoothstep(0.38,0.49,abs(card_uv.x-0.5))*smoothstep(0.40,0.49,abs(card_uv.y-0.5));
	float stroke = sin(UV.y*171.0 + UV.x*83.0)*0.10 + sin(UV.y*391.0-UV.x*243.0)*0.05;
	float width = 1.45+edge_wear*2.15+corner*0.35+stroke;
	vec2 unit = TEXTURE_PIXEL_SIZE * source_pixels_per_unit;
	float outer = paper.a;
	float inner = paper.a;
	for (int i=0; i<12; i++) {
		float angle = float(i)*6.2831853/12.0;
		vec2 direction = vec2(cos(angle),sin(angle));
		outer = min(outer,texture(TEXTURE,UV+direction*unit*0.55).a);
		inner = min(inner,texture(TEXTURE,UV+direction*unit*width).a);
	}
	float grain = texture(gold_noise,UV*vec2(3.0,4.7)).r;
	float sheen = texture(gold_noise,UV*vec2(0.7,1.3)+vec2(shimmer_clock*0.005,0.0)).r;
	float facets = clamp(0.5+(grain-0.5)*0.22+(sheen-0.5)*0.16,0.0,1.0);
	vec3 gold = mix(vec3(0.82,0.72,0.46),vec3(0.98,0.88,0.64),facets);
	float highlight = smoothstep(0.40,0.80,sheen);
	gold = mix(gold,vec3(1.0,0.95,0.77),highlight*0.16);
	gold += vec3(1.0,0.93,0.70)*emission_strength*(0.45+0.15*highlight);
	float paper_cover = texture(gold_noise,card_uv*vec2(1.20,1.85)+vec2(0.37,0.72)).r;
	float exposed = mix(0.84,1.0,smoothstep(0.18,0.78,paper_cover));
	vec2 title_uv = (card_uv-vec2(0.15,-0.045))/vec2(0.70,0.13);
	float title_mask = 0.0;
	if (cutout_title && all(greaterThanEqual(title_uv,vec2(0.0))) && all(lessThanEqual(title_uv,vec2(1.0)))) {
		vec2 size = vec2(textureSize(title_paper,0));
		title_mask = texture(title_paper,(vec2(110.0,196.0)+title_uv*vec2(1810.0,380.0))/size).a;
	}
	COLOR = vec4(gold,outer*(1.0-inner)*strength*(1.0-title_mask)*exposed);
}
