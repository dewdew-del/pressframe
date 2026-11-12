#version 460 core
#include <flutter/runtime_effect.glsl>

precision highp float;

// Every uniform is a vec4 so there is no padding for a graphics backend to disagree on.
uniform vec4 uRowX;   // xyz: output pixel -> source u,  w: sharpen step in u
uniform vec4 uRowY;   // xyz: output pixel -> source v,  w: sharpen step in v
uniform vec4 uLight;  // exposure, contrast, highlights, shadows
uniform vec4 uColor;  // temperature, tint, saturation, vibrance
uniform vec4 uDetail; // x: sharpen
uniform sampler2D uTex;

out vec4 fragColor;

const vec3 LUMA = vec3(0.2126, 0.7152, 0.0722);

void main() {
  vec3 p = vec3(FlutterFragCoord().xy, 1.0);
  vec2 uv = vec2(dot(uRowX.xyz, p), dot(uRowY.xyz, p));
  if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
    fragColor = vec4(0.0, 0.0, 0.0, 1.0);
    return;
  }
  vec2 t = vec2(uRowX.w, uRowY.w);

  vec3 c = texture(uTex, uv).rgb;
  vec3 n = texture(uTex, uv - vec2(0.0, t.y)).rgb;
  vec3 s = texture(uTex, uv + vec2(0.0, t.y)).rgb;
  vec3 e = texture(uTex, uv + vec2(t.x, 0.0)).rgb;
  vec3 w = texture(uTex, uv - vec2(t.x, 0.0)).rgb;
  c += uDetail.x * (4.0 * c - n - s - e - w);

  vec3 lin = pow(max(c, 0.0), vec3(2.2)) * exp2(uLight.x);
  lin.r *= 1.0 + 0.25 * uColor.x;
  lin.b *= 1.0 - 0.25 * uColor.x;
  lin.g *= 1.0 - 0.25 * uColor.y;
  c = pow(lin, vec3(1.0 / 2.2));

  float L = dot(c, LUMA);
  c += uLight.w * 0.35 * (1.0 - L) * (1.0 - L) + uLight.z * 0.35 * L * L;
  c = (c - 0.5) * (1.0 + uLight.y) + 0.5;

  L = dot(c, LUMA);
  c = mix(vec3(L), c, 1.0 + uColor.z);
  float sat = max(c.r, max(c.g, c.b)) - min(c.r, min(c.g, c.b));
  c = mix(vec3(L), c, 1.0 + uColor.w * (1.0 - sat));

  fragColor = vec4(clamp(c, 0.0, 1.0), 1.0);
}
