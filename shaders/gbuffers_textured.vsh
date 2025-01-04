#version 460 compatibility

in vec3 mc_Entity;

out vec2 texCoord;
out vec2 lightCoord;
out vec4 vertexColor;
out float vertexDistance;
out vec3 normal;
out vec3 viewSpacePosition;
out float blockId;
out vec3 shadowLightDirection;
out vec3 screenPos;

uniform vec3 shadowLightPosition;
uniform mat4 gbufferModelViewInverse;

void main() {
    blockId = mc_Entity.x;
    shadowLightDirection = normalize(mat3(gbufferModelViewInverse) * shadowLightPosition);

    // distance for fog
    vertexDistance = length((gl_ModelViewMatrix * gl_Vertex).xyz);

    // classic stuff
    normal = gl_NormalMatrix * gl_Normal;
    gl_Position = gl_ModelViewProjectionMatrix * gl_Vertex;
    screenPos = (gl_ModelViewProjectionMatrix * gl_Vertex).xyz;
    texCoord = gl_MultiTexCoord0.xy;
    lightCoord = (gl_TextureMatrix[1] * gl_MultiTexCoord1).xy;
    vertexColor = gl_Color;

    viewSpacePosition = (gl_ModelViewMatrix * gl_Vertex).xyz;
}