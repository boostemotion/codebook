#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;
uniform float uStrength;

out vec4 fragColor;

void main() {
  vec2 uv = FlutterFragCoord().xy / uSize;
  vec2 center = uv - vec2(0.5, 0.5);
  float radius = length(center);

  float edge = smoothstep(0.52, 0.14, radius);
  float rim = smoothstep(0.58, 0.25, radius) - smoothstep(0.48, 0.13, radius);

  vec2 lightDir = normalize(vec2(-0.8, -1.2));
  float directional = clamp(dot(normalize(center + vec2(0.0001)), lightDir), -1.0, 1.0);
  directional = directional * 0.5 + 0.5;

  float caustic = sin((uv.x + uv.y) * 24.0) * 0.5 + 0.5;
  float glow = mix(0.06, 0.28, directional) * edge;
  glow += rim * 0.16;
  glow += caustic * 0.03 * edge;
  glow *= uStrength;

  vec3 color = vec3(0.98, 0.95, 0.97) * glow;
  fragColor = vec4(color, clamp(glow, 0.0, 0.22));
}
