shader_type spatial;
render_mode depth_draw_opaque, cull_disabled, diffuse_burley, specular_disabled;
uniform sampler2D static_texture : source_color, filter_linear_mipmap_anisotropic;
uniform float elapsed = 0.0;
uniform float wind_strength = 0.105;
uniform float wind_speed = 1.05;
uniform float bend_strength = 1.0;
uniform float interaction_strength = 0.30;
uniform float disturbance_radius = 1.30;
uniform vec4 events[32];
uniform vec4 directions[32];
uniform vec4 segments[32];
uniform float region_strength = 0.78;
uniform float saturation = 0.72;
uniform float variation_strength = 0.10;
uniform vec3 natural_multiplier = vec3(0.96,0.78,0.72);
uniform vec3 facing_right = vec3(1.0,0.0,0.0);
uniform vec3 facing_up = vec3(0.0,0.309017,-0.951057);
uniform vec3 facing_forward = vec3(0.0,0.951057,0.309017);
varying float tint;
varying float macro_tint;
float hash(vec2 p) { return fract(sin(dot(p,vec2(127.1,311.7))) * 43758.5453123); }
float noise(vec2 p) {
	vec2 cell=floor(p); vec2 f=fract(p); f=f*f*(3.0-2.0*f);
	return mix(mix(hash(cell),hash(cell+vec2(1,0)),f.x),mix(hash(cell+vec2(0,1)),hash(cell+vec2(1,1)),f.x),f.y);
}
vec2 safe_dir(vec2 p) { return length(p)>0.001 ? normalize(p) : vec2(1,0); }
void vertex() {
	vec2 anchor=vec2(MODEL_MATRIX[3].x,INSTANCE_CUSTOM.b);
	vec3 root=MODEL_MATRIX[3].xyz;
	vec3 camera_right=normalize(facing_right);
	vec3 camera_up=normalize(facing_up);
	vec3 camera_forward=normalize(facing_forward);
	float phase=INSTANCE_CUSTOM.r*6.2831853;
	float instance_scale=INSTANCE_CUSTOM.w;
	tint=INSTANCE_CUSTOM.g;
	vec2 field=anchor/2.0;
	macro_tint=clamp(noise(field*0.72+vec2(2.7,8.1))*0.72+noise(field*1.43+vec2(11.6,3.4))*0.28,0.0,1.0);
	vec2 wind_dir=normalize(vec2(1.0,0.24));
	float primary=pow(sin(dot(anchor,wind_dir)*0.42-elapsed*wind_speed+phase*0.17)*0.5+0.5,1.55);
	float detail=sin(dot(anchor,vec2(-wind_dir.y,wind_dir.x))*1.30+elapsed*1.7+phase*1.73)*0.5+0.5;
	float wind=wind_strength*(0.18+primary*0.64+detail*0.18)*mix(0.78,1.16,tint);
	float push=0.0;
	float total_weight=0.0;
	for(int i=0;i<32;i++) {
		float age=elapsed-events[i].z;
		vec2 travel=segments[i].zw-segments[i].xy;
		float along=clamp(dot(anchor-segments[i].xy,travel)/max(dot(travel,travel),0.0001),0.0,1.0);
		vec2 radial=anchor-mix(segments[i].xy,segments[i].zw,along);
		float falloff=1.0-smoothstep(disturbance_radius*0.28,disturbance_radius,length(radial));
		float envelope=age>=0.0 && age<1.1 ? exp(-age*4.4)*events[i].w*falloff : 0.0;
		vec2 radial_soft=radial/max(disturbance_radius*0.4,length(radial));
		vec3 movement=vec3(radial_soft.x+directions[i].x*0.72,0.0,radial_soft.y+directions[i].y*0.72);
		float lateral=clamp(dot(movement,camera_right),-1.0,1.0);
		push+=lateral*sin(age*11.0)*envelope;
		total_weight+=envelope;
	}
	push=clamp(push/max(1.0,total_weight),-1.0,1.0)*interaction_strength;
	float root_mask=pow(clamp(1.0-UV.y,0.0,1.0),1.75);
	float wind_lateral=dot(vec3(wind_dir.x,0.0,wind_dir.y),camera_right)*wind;
	VERTEX.x+=(wind_lateral+push)*root_mask*bend_strength/max(instance_scale,0.01);
	MODELVIEW_MATRIX=VIEW_MATRIX*mat4(vec4(camera_right*instance_scale,0.0),vec4(camera_up*instance_scale,0.0),vec4(camera_forward*instance_scale,0.0),vec4(root,1.0));
	MODELVIEW_NORMAL_MATRIX=mat3(VIEW_MATRIX)*mat3(camera_right,camera_up,camera_forward);
}
void fragment() {
	vec4 grass=texture(static_texture,UV);
	if(grass.a<0.18) { discard; }
	vec3 multiplier=mix(vec3(1),mix(vec3(0.88,0.99,1.08),vec3(1.08,1.02,0.88),tint),variation_strength);
	float shadow=1.0-smoothstep(0.32,0.44,macro_tint);
	float sunlit=smoothstep(0.56,0.68,macro_tint);
	vec3 region=vec3(0.12,0.32,0.28)*shadow+vec3(0.28,0.54,0.28)*max(0.0,1.0-shadow-sunlit)+vec3(0.60,0.72,0.34)*sunlit;
	vec3 original=grass.rgb*multiplier;
	float value=mix(0.72,1.28,max(original.r,max(original.g,original.b)));
	vec3 painted=mix(original,region*value,region_strength);
	float luminance=dot(painted,vec3(0.2126,0.7152,0.0722));
	ALBEDO=mix(vec3(luminance),painted,saturation)*natural_multiplier;
	ROUGHNESS=0.95;
}

