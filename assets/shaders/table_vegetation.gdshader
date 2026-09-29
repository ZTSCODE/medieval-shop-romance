shader_type canvas_item;
render_mode unshaded;
uniform float elapsed = 0.0;
uniform float wind_strength = 8.0;
uniform float wind_speed = 1.05;
uniform float interaction_strength = 30.0;
uniform float disturbance_radius = 130.0;
uniform vec4 board_rect;
uniform vec4 events[8];
uniform vec4 directions[8];
uniform float region_strength = 0.78;
uniform float saturation = 0.72;
uniform float variation_strength = 0.10;
uniform vec3 natural_multiplier = vec3(0.96,0.78,0.72);
varying vec2 world_point;
varying float tint;
varying float macro_tint;
float hash(vec2 p) { return fract(sin(dot(p,vec2(127.1,311.7))) * 43758.5453123); }
float noise(vec2 p) {
	vec2 cell=floor(p); vec2 f=fract(p); f=f*f*(3.0-2.0*f);
	return mix(mix(hash(cell),hash(cell+vec2(1,0)),f.x),mix(hash(cell+vec2(0,1)),hash(cell+vec2(1,1)),f.x),f.y);
}
vec2 safe_dir(vec2 p) { return length(p)>0.001 ? normalize(p) : vec2(1,0); }
void vertex() {
	vec2 anchor=INSTANCE_CUSTOM.xy;
	float phase=INSTANCE_CUSTOM.z*6.2831853;
	float instance_scale=INSTANCE_CUSTOM.w;
	tint=fract(INSTANCE_CUSTOM.z*7.13);
	vec2 field=anchor/200.0;
	macro_tint=clamp(noise(field*0.72+vec2(2.7,8.1))*0.72+noise(field*1.43+vec2(11.6,3.4))*0.28,0.0,1.0);
	vec2 wind_dir=normalize(vec2(1.0,0.24));
	float primary=pow(sin(dot(anchor,wind_dir)*0.0042-elapsed*wind_speed+phase*0.17)*0.5+0.5,1.55);
	float detail=sin(dot(anchor,vec2(-wind_dir.y,wind_dir.x))*0.013+elapsed*1.7+phase*1.73)*0.5+0.5;
	float wind=wind_strength*(0.18+primary*0.64+detail*0.18)*mix(0.78,1.16,tint);
	vec2 push=vec2(0);
	for(int i=0;i<8;i++) {
		float age=elapsed-events[i].z;
		vec2 radial=anchor-events[i].xy;
		float falloff=1.0-smoothstep(disturbance_radius*0.28,disturbance_radius,length(radial));
		float response=age>=0.0 ? sin(age*11.0)*exp(-age*4.4)*events[i].w : 0.0;
		push+=safe_dir(safe_dir(radial)+directions[i].xy*0.72)*falloff*response*interaction_strength;
	}
	push=clamp(push,vec2(-55),vec2(55));
	float root_mask=pow(clamp(1.0-UV.y,0.0,1.0),1.75);
	VERTEX+=vec2(wind+push.x,push.y+abs(push.x)*0.24)*root_mask/max(instance_scale,0.01);
	world_point=anchor+VERTEX*instance_scale;
}
void fragment() {
	if(world_point.x>=board_rect.x && world_point.x<=board_rect.x+board_rect.z && world_point.y>=board_rect.y && world_point.y<=board_rect.y+board_rect.w) { discard; }
	vec4 grass=texture(TEXTURE,UV);
	vec3 multiplier=mix(vec3(1),mix(vec3(0.88,0.99,1.08),vec3(1.08,1.02,0.88),tint),variation_strength);
	float shadow=1.0-smoothstep(0.32,0.44,macro_tint);
	float sunlit=smoothstep(0.56,0.68,macro_tint);
	vec3 region=vec3(0.12,0.32,0.28)*shadow+vec3(0.28,0.54,0.28)*max(0.0,1.0-shadow-sunlit)+vec3(0.60,0.72,0.34)*sunlit;
	vec3 original=grass.rgb*multiplier;
	float value=mix(0.72,1.28,max(original.r,max(original.g,original.b)));
	vec3 painted=mix(original,region*value,region_strength);
	float luminance=dot(painted,vec3(0.2126,0.7152,0.0722));
	COLOR=vec4(mix(vec3(luminance),painted,saturation)*natural_multiplier,grass.a);
}
