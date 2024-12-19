#version 460 compatibility

#define AMBIENT 0.5
#define SHADOW_BRIGHTNESS 0.5
#define MAX_RAY_DEPTH 40
#define RAY_STEP 0.05
#define RAY_SAMPLES 100
#define RAY_COEF 0.003

in vec2 texCoord;
in vec2 lightCoord;
in vec4 vertexColor;
in float vertexDistance;
in vec3 normal;
in vec3 viewSpacePosition;
in float blockId;
in vec3 shadowLightDirection;

// Con`lzni|verse8663

// texture
uniform sampler2D gtexture;

// fog uniforms
uniform float fogStart;
uniform float fogEnd;
uniform vec3 fogColor;

// matrices
uniform mat4 gbufferModelViewInverse;
uniform mat4 shadowModelView;
uniform mat4 shadowProjection;

// shadow uniforms
uniform sampler2D depthtex0;
uniform sampler2D shadowtex0;
uniform sampler2D shadowtex1;
uniform sampler2D shadowcolor0;

// camera
uniform vec3 cameraPosition;

// lighting uniforms
uniform int heldBlockLightValue;
uniform sampler2D lightmap;

#include "/programs/distort.glsl"

layout(location = 0) out vec4 pixelColor;

struct Ray {
    vec3 o;
    vec3 d;
    vec3 accumulatedLight;
} ray;

float sampleShadowMap(mat3 mat, vec3 uv) {
    float sampleStrength = 1;
    for(int i = -1; i < 2; i++) {
        for(int j = -1; j < 2; j++) {
            if(step(uv.z,texture(shadowtex0,vec2(uv.x + i, uv.y + j)).r) == 0.0) { //distort i and j fleeeeemme ; update ah putaaaaiiin
                sampleStrength -= 0.05;
            }
        }
    }
    return sampleStrength;
}

vec3 convertToShadowSpace(vec3 worldPos, vec3 worldNormal) {
    vec3 adjustFragFeetPlayerSpace = worldPos + worldNormal * .03;
    vec3 fragShadowViewSpace = (shadowModelView * vec4(adjustFragFeetPlayerSpace,1.0)).xyz;
    vec4 fragHomogeneousSpace = shadowProjection * vec4(fragShadowViewSpace,1.0);
    vec3 fragShadowNdcSpace = fragHomogeneousSpace.xyz/fragHomogeneousSpace.w;
    vec3 distortedFragShadowNdcSpace = vec3(distort(fragShadowNdcSpace.xy),fragShadowNdcSpace.z);
    vec3 fragShadowScreenSpace = distortedFragShadowNdcSpace * 0.5 + 0.5;
    return fragShadowScreenSpace;
}

void main() {
    vec3 sunlight = vec3(0.99, 0.98, 0.82);

    // PCF matrix
    mat3 sampleMat = mat3(1/9, 1/9, 1/9, 1/9, 1/9, 1/9, 1/9, 1/9, 1/9);

    // get lightmap coords from input
    vec2 lm = lightCoord;

    // world coords
    vec3 worldNormal = mat3(gbufferModelViewInverse) * normal;
    vec4 worldPosition = gbufferModelViewInverse * vec4(viewSpacePosition,1.0);

    // get texture and discard if transparent
    vec4 texColor = texture(gtexture, texCoord);
    if(texColor.a < 0.1) discard;

    // initiate final color from texture and vertex color
    vec4 finalColor = texColor * vertexColor;

    // convert fragment position to shadow space
    vec3 fragShadowScreenSpace = convertToShadowSpace(worldPosition.xyz, worldNormal);

    // sample shadowmap
    float isInShadow = step(fragShadowScreenSpace.z,texture(shadowtex0,fragShadowScreenSpace.xy).r);
    float isInNonColoredShadow = step(fragShadowScreenSpace.z,texture(shadowtex1,fragShadowScreenSpace.xy).r);
    vec3 shadowColor = pow(texture(shadowcolor0,fragShadowScreenSpace.xy).rgb,vec3(2.2));

    // normal dot light direction
    float NdotL = clamp(dot(worldNormal, shadowLightDirection), AMBIENT, 1.0);

    // change lightmap coords based on shadow
    if(isInShadow == 0.0 && dot(worldNormal, shadowLightDirection) > 0.1) { // is in shadow but not completely orthogonal to light
        if(isInNonColoredShadow == 0.0) { // full shadow
            //float shadowMultiplier = sampleShadowMap(sampleMat, fragShadowScreenSpace);
            lm.y *= SHADOW_BRIGHTNESS;
        } else { // colored shadow
            lm.y = mix(31.0 / 32.0 * SHADOW_BRIGHTNESS, 31.0 / 32.0, sqrt(NdotL)); // apply light from sun
            vec4 shadowLightColor = texture2D(shadowcolor0, fragShadowScreenSpace.xy); // sample shadow color

            // mix shadow color based on light and alpha
            shadowLightColor.rgb = mix(vec3(1.0), shadowLightColor.rgb, shadowLightColor.a);
            shadowLightColor.rgb = mix(shadowLightColor.rgb, vec3(1.0), lm.x);

            finalColor.rgb *= shadowLightColor.rgb; // apply shadow color to pixel color
        }
    } else if(dot(worldNormal, shadowLightDirection) < 0.1){ // orthogonal to light source => shadow but not shadowmap
        lm.y *= SHADOW_BRIGHTNESS;
    } else { // not in shadow
        lm.y = mix(31.0 / 32.0 * (NdotL), 31.0 / 32.0, sqrt(NdotL)); // apply light from sun (normal dot light direction)
    }

    // Volumetric fog
    ray.o = vec3(0, 0, 0);
    ray.d = normalize(worldPosition.xyz);
    ray.accumulatedLight = vec3(0);

    vec3 shadowSamplePos;
    vec3 samplePoint = ray.o;
    float dist = 0;

    for(int i = 0; i < RAY_SAMPLES; i++) {

        if(dist > vertexDistance) {
            break;
        }
        if(dist > MAX_RAY_DEPTH) {
            break;
        }

        // convert point to shadowmap space
        shadowSamplePos = convertToShadowSpace(samplePoint, worldNormal);

        //sample shadowmap and accumulate light/colored light
        float isShadow = step(shadowSamplePos.z,texture(shadowtex0,shadowSamplePos.xy).r);

        if(isShadow != 0.0) {
            ray.accumulatedLight += RAY_COEF * sunlight;
        }
        else {
            float isInNonColoredShadow = step(shadowSamplePos.z,texture(shadowtex1,shadowSamplePos.xy).r);
            if(isInNonColoredShadow != 0) {
                vec3 shadowColor = pow(texture(shadowcolor0,shadowSamplePos.xy).rgb,vec3(2.2));
                ray.accumulatedLight += RAY_COEF * shadowColor;
            }
        }

        // advance ray by step and increase distance
        float rayStep = pow(i/20, 2) * RAY_STEP;
        samplePoint += ray.d * rayStep;
        dist += rayStep;
    }

    // sample lightmap with modified light coords
    vec4 lightColor = texture(lightmap, lm);

    // apply lightmap to color
    finalColor *= lightColor;

    // apply accumulated light
    finalColor.xyz += ray.accumulatedLight;

    // fog based on distance
    float fogValue = vertexDistance < fogEnd ? smoothstep(fogStart, fogEnd, vertexDistance) : 1.0;

    // apply fog to final color based on fog value
    finalColor = vec4(mix(finalColor.xyz, fogColor, fogValue), finalColor.a);

    // apply color to pixel
    pixelColor = finalColor;
}