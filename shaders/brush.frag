#version 460 core
precision highp float;

#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;
uniform vec4 uA;  // mode, amount
uniform sampler2D uImage;
uniform sampler2D uMask;

out vec4 fragColor;

void main() {
  vec2 uv = FlutterFragCoord().xy / uSize;
  vec3 c = texture(uImage, uv).rgb;
  float k = uA.y * texture(uMask, uv).a;
  int mode = int(uA.x + 0.5);
  float g = dot(c, vec3(0.299, 0.587, 0.114));
  if (k > 0.001) {
    if (mode == 0) {
      c = 1.0 - (1.0 - c) * (1.0 - 0.45 * k);
    } else if (mode == 1) {
      c *= 1.0 - 0.55 * k;
    } else if (mode == 2) {
      c.r += 0.12 * k;
      c.b -= 0.12 * k;
    } else if (mode == 3) {
      c.r -= 0.12 * k;
      c.b += 0.12 * k;
    } else if (mode == 4) {
      c = mix(vec3(g), c, 1.0 + 0.9 * k);
    } else if (mode == 5) {
      c = mix(vec3(g), c, 1.0 - 0.9 * k);
    } else {
      vec2 o = vec2(6.0 / 1280.0, 6.0 / 1280.0 * uSize.x / uSize.y);
      vec3 acc = c;
      for (int i = 0; i < 8; i++) {
        float a = float(i) * 0.7853982;
        acc += texture(uImage, clamp(uv + vec2(cos(a), sin(a)) * o, vec2(0.0), vec2(1.0))).rgb;
      }
      c = mix(c, acc / 9.0, clamp(k, 0.0, 1.0));
    }
  }
  fragColor = vec4(clamp(c, 0.0, 1.0), 1.0);
}
