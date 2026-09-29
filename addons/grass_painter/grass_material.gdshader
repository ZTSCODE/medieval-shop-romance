shader_type spatial;
render_mode depth_draw_opaque, cull_disabled, diffuse_burley, specular_disabled;

uniform sampler2D static_texture : source_color, filter_linear_mipmap_anisotropic;
uniform float alpha_scissor : hint_range(0.0,1.0,0.01) = 0.18;
uniform bool flip_horizontal = false;
uniform bool wind_enabled = true;
uniform bool player_interaction_enabled = true;
uniform bool color_adjustment_enabled = true;
uniform float elapsed = 0.0;
uniform vec2 wind_direction = vec2(1.0,0.24);
uniform float wind_strength = 0.105;
uniform float wind_speed = 1.05;
uniform float wind_wave_scale = 0.42;
uniform float wind_detail_scale = 1.30;
uniform float wind_detail_speed = 1.70;
uniform float wind_wave_sharpness = 1.55;
uniform float wind_root_power = 1.75;
uniform float bend_strength = 1.0;
uniform float interaction_strength = 0.30;
uniform float disturbance_radius = 1.30;
uniform vec4 events[32];
uniform vec4 directions[32];
uniform vec4 segments[32];
uniform float region_color_strength = 0.78;
uniform float region_size_meters = 4.5;
uniform float color_saturation = 0.72;
uniform float color_variation_strength = 0.10;
uniform float shape_variation_strength = 0.08;
uniform vec3 natural_color_multiplier = vec3(0.96,0.78,0.72);
uniform vec3 cool_color_multiplier = vec3(0.88,0.99,1.08);
uniform vec3 warm_color_multiplier = vec3(1.08,1.02,0.88);
uniform vec3 shadow_region_multiplier = vec3(0.12,0.32,0.28);
uniform vec3 base_region_multiplier = vec3(0.28,0.54,0.28);
uniform vec3 sunlit_region_multiplier = vec3(0.60,0.72,0.34);
uniform float region_transition_softness = 0.06;
uniform vec3 facing_right = vec3(1.0,0.0,0.0);
uniform vec3 facing_up = vec3(0.0,0.309017,-0.951057);
uniform vec3 facing_forward = vec3(0.0,0.951057,0.309017);
uniform bool pointer_light_enabled = false;
uniform vec3 pointer_light_position = vec3(0.0);
uniform float pointer_light_range = 4.5;
uniform float pointer_light_energy = 0.0;
uniform vec3 pointer_light_color = vec3(1.0,0.78,0.56);
uniform vec3 player_position = vec3(0.0);
uniform vec3 player_velocity = vec3(0.0);
uniform float disturbance_speed_threshold = 0.2;
uniform float player_bend_strength = 0.30;
uniform float player_vertical_compression = 0.0;
uniform float outline_width_pixels = 0.0;
uniform float outline_strength = 0.0;
uniform vec3 outline_color = vec3(0.10,0.15,0.09);
uniform float outline_forward_distance_limit = 0.0;

varying float tint;
varying float macro_tint;
varying vec3 billboard_world_position;

float hash_value(vec2 point) {
	return fract(sin(dot(point,vec2(127.1,311.7))) * 43758.5453123);
}

float field_noise(vec2 point) {
	vec2 cell = floor(point);
	vec2 local = fract(point);
	local = local * local * (3.0 - 2.0 * local);
	return mix(mix(hash_value(cell),hash_value(cell+vec2(1.0,0.0)),local.x),mix(hash_value(cell+vec2(0.0,1.0)),hash_value(cell+vec2(1.0,1.0)),local.x),local.y);
}

vec2 safe_direction(vec2 value) {
	return length(value) > 0.001 ? normalize(value) : vec2(1.0,0.0);
}

void vertex() {
	vec2 anchor = vec2(MODEL_MATRIX[3].x,INSTANCE_CUSTOM.b);
	vec3 root = MODEL_MATRIX[3].xyz;
	vec3 camera_right = normalize(facing_right);
	vec3 camera_up = normalize(facing_up);
	vec3 camera_forward = normalize(facing_forward);
	float phase = INSTANCE_CUSTOM.r * 6.2831853;
	float instance_scale = INSTANCE_CUSTOM.w;
	tint = INSTANCE_CUSTOM.g;
	vec2 field = anchor / max(region_size_meters,0.1);
	macro_tint = clamp(field_noise(field*0.72+vec2(2.7,8.1))*0.72+field_noise(field*1.43+vec2(11.6,3.4))*0.28,0.0,1.0);
	vec2 wind_dir = safe_direction(wind_direction);
	float primary = pow(sin(dot(anchor,wind_dir)*wind_wave_scale-elapsed*wind_speed+phase*0.17)*0.5+0.5,wind_wave_sharpness);
	float detail = sin(dot(anchor,vec2(-wind_dir.y,wind_dir.x))*wind_detail_scale+elapsed*wind_detail_speed+phase*1.73)*0.5+0.5;
	float wind = wind_enabled ? wind_strength*(0.18+primary*0.64+detail*0.18)*mix(0.78,1.16,tint) : 0.0;
	float push = 0.0;
	float total_weight = 0.0;
	if (player_interaction_enabled) {
		for(int index=0;index<32;index++) {
			float age = elapsed-events[index].z;
			vec2 travel = segments[index].zw-segments[index].xy;
			float along = clamp(dot(anchor-segments[index].xy,travel)/max(dot(travel,travel),0.0001),0.0,1.0);
			vec2 radial = anchor-mix(segments[index].xy,segments[index].zw,along);
			float falloff = 1.0-smoothstep(disturbance_radius*0.28,disturbance_radius,length(radial));
			float envelope = age>=0.0 && age<1.1 ? exp(-age*4.4)*events[index].w*falloff : 0.0;
			vec2 radial_soft = radial/max(disturbance_radius*0.4,length(radial));
			vec3 movement = vec3(radial_soft.x+directions[index].x*0.72,0.0,radial_soft.y+directions[index].y*0.72);
			float lateral = clamp(dot(movement,camera_right),-1.0,1.0);
			push += lateral*sin(age*11.0)*envelope;
			total_weight += envelope;
		}
	}
	push = clamp(push/max(1.0,total_weight),-1.0,1.0)*interaction_strength;
	float root_mask = pow(clamp(1.0-UV.y,0.0,1.0),wind_root_power);
	float width_seed = fract(INSTANCE_CUSTOM.r*7.13+INSTANCE_CUSTOM.g*3.71);
	VERTEX.x *= mix(1.0-shape_variation_strength,1.0+shape_variation_strength,width_seed);
	float wind_lateral = dot(vec3(wind_dir.x,0.0,wind_dir.y),camera_right)*wind;
	VERTEX.x += (wind_lateral+push)*root_mask*bend_strength/max(instance_scale,0.01);
	billboard_world_position = root+camera_right*(VERTEX.x*instance_scale)+camera_up*(VERTEX.y*instance_scale)+camera_forward*(VERTEX.z*instance_scale);
	MODELVIEW_MATRIX = VIEW_MATRIX*mat4(vec4(camera_right*instance_scale,0.0),vec4(camera_up*instance_scale,0.0),vec4(camera_forward*instance_scale,0.0),vec4(root,1.0));
	MODELVIEW_NORMAL_MATRIX = mat3(VIEW_MATRIX)*mat3(camera_right,camera_up,camera_forward);
}

void fragment() {
	vec2 plant_uv = vec2(flip_horizontal ? 1.0-UV.x : UV.x,UV.y);
	vec4 grass = texture(static_texture,plant_uv);
	if (grass.a < alpha_scissor) {
		discard;
	}
	vec3 multiplier = mix(vec3(1.0),mix(cool_color_multiplier,warm_color_multiplier,tint),color_variation_strength);
	float shadow = 1.0-smoothstep(0.38-region_transition_softness,0.38+region_transition_softness,macro_tint);
	float sunlit = smoothstep(0.62-region_transition_softness,0.62+region_transition_softness,macro_tint);
	float base = max(0.0,1.0-shadow-sunlit);
	vec3 region = shadow_region_multiplier*shadow+base_region_multiplier*base+sunlit_region_multiplier*sunlit;
	vec3 original = grass.rgb*multiplier;
	float value = mix(0.72,1.28,max(original.r,max(original.g,original.b)));
	vec3 painted = mix(original,region*value,region_color_strength);
	if (color_adjustment_enabled) {
		float luminance = dot(painted,vec3(0.2126,0.7152,0.0722));
		painted = mix(vec3(luminance),painted,color_saturation)*natural_color_multiplier;
	}
	ALBEDO = painted;
	float pointer_distance = distance(billboard_world_position,pointer_light_position);
	float pointer_falloff = pointer_light_enabled ? 1.0-smoothstep(pointer_light_range*0.12,pointer_light_range,pointer_distance) : 0.0;
	EMISSION = painted*pointer_light_color*pointer_falloff*pointer_light_energy*0.22;
	ROUGHNESS = 0.95;
}
