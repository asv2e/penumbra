#version 460 core
precision highp float;

#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;
uniform vec4 uH0;  // cx, cy, radius (height units), type (0 move, 1 bulge, 2 rotate)
uniform vec4 uD0;  // dx, dy, strength, angle
uniform vec4 uH1;
uniform vec4 uD1;
uniform vec4 uH2;
uniform vec4 uD2;
uniform vec4 uH3;
uniform vec4 uD3;
uniform vec4 uH4;
uniform vec4 uD4;
uniform vec4 uH5;
uniform vec4 uD5;
uniform vec4 uH6;
uniform vec4 uD6;
uniform vec4 uH7;
uniform vec4 uD7;
uniform sampler2D uImage;

out vec4 fragColor;

vec2 handle(vec2 p, vec4 h, vec4 d) {
  if (h.z <= 0.0) return p;
  vec2 asp = vec2(uSize.x / uSize.y, 1.0);
  vec2 v = (p - h.xy) * asp;
  float r = length(v) / h.z;
  if (r >= 1.0) return p;
  float f = 1.0 - smoothstep(0.0, 1.0, r);
  if (h.w < 0.5) return p - d.xy * f;
  if (h.w < 1.5) return h.xy + (p - h.xy) * (1.0 - d.z * f);
  float a = d.w * f;
  vec2 q = (p - h.xy) * asp;
  vec2 rq = vec2(q.x * cos(a) + q.y * sin(a), -q.x * sin(a) + q.y * cos(a));
  return h.xy + rq / asp;
}

void main() {
  vec2 uv = FlutterFragCoord().xy / uSize;
  vec2 p = uv;
  p = handle(p, uH0, uD0);
  p = handle(p, uH1, uD1);
  p = handle(p, uH2, uD2);
  p = handle(p, uH3, uD3);
  p = handle(p, uH4, uD4);
  p = handle(p, uH5, uD5);
  p = handle(p, uH6, uD6);
  p = handle(p, uH7, uD7);
  fragColor = vec4(texture(uImage, clamp(p, vec2(0.0), vec2(1.0))).rgb, 1.0);
}
