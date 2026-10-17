#version 460 core
precision highp float;

#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;
uniform vec4 uA;     // sharpen, structure, clarity, texture
uniform vec4 uB;     // dehaze, tcLow, tcMid, tcHigh
uniform vec4 uC;     // smooth, denoise, deblur, caAmount
uniform vec4 uD;     // blur, blurSize, blurFeather, blurShape
uniform vec4 uE;     // blurCx, blurCy, motion, motionAngle
uniform vec4 uF;     // skinSmooth, faceLight, eyeBright, eyeRadius
uniform vec4 uFace;  // cx, cy, rx, ry (rx <= 0: no face)
uniform vec4 uEyes;  // lx, ly, rx, ry
uniform vec4 uG;     // ambiance
uniform sampler2D uImage;

out vec4 fragColor;

vec3 tap(vec2 uv) {
  return texture(uImage, clamp(uv, vec2(0.0), vec2(1.0))).rgb;
}

// Offset of `px` pixels on a 1280px wide image, expressed in UV space.
vec2 off(float px) {
  float x = px / 1280.0;
  return vec2(x, x * uSize.x / uSize.y);
}

float luma(vec3 c) {
  return dot(c, vec3(0.299, 0.587, 0.114));
}

vec3 ring(vec2 uv, float px) {
  vec3 acc = tap(uv);
  vec2 o = off(px);
  for (int i = 0; i < 8; i++) {
    float a = float(i) * 0.7853982;
    acc += tap(uv + vec2(cos(a), sin(a)) * o);
  }
  return acc / 9.0;
}

vec3 wide(vec2 uv, float px) {
  vec3 acc = tap(uv);
  for (int i = 0; i < 8; i++) {
    float a = float(i) * 0.7853982;
    vec2 d = vec2(cos(a), sin(a));
    acc += tap(uv + d * off(px));
    acc += tap(uv + d * off(px * 0.5));
  }
  return acc / 17.0;
}

vec3 bilateral(vec2 uv, vec3 c, float px, float sigma) {
  vec3 acc = c;
  float ws = 1.0;
  vec2 o = off(px);
  for (int i = 0; i < 8; i++) {
    float a = float(i) * 0.7853982;
    vec2 d = vec2(cos(a), sin(a));
    vec3 s1 = tap(uv + d * o);
    vec3 s2 = tap(uv + d * o * 0.5);
    vec3 e1 = s1 - c;
    vec3 e2 = s2 - c;
    float w1 = exp(-dot(e1, e1) / sigma);
    float w2 = exp(-dot(e2, e2) / sigma);
    acc += s1 * w1 + s2 * w2;
    ws += w1 + w2;
  }
  return acc / ws;
}

vec3 disk(vec2 uv, vec2 r) {
  vec3 acc = vec3(0.0);
  for (int i = 0; i < 16; i++) {
    float fi = float(i);
    float a = fi * 2.3999632;
    float rad = sqrt((fi + 0.5) / 16.0);
    acc += tap(uv + vec2(cos(a), sin(a)) * rad * r);
  }
  return acc / 16.0;
}

void main() {
  vec2 uv = FlutterFragCoord().xy / uSize;
  float aspect = uSize.x / uSize.y;
  vec3 c = tap(uv);

  // Chromatic aberration (lateral fringe shift, + or -).
  if (abs(uC.w) > 0.001) {
    vec2 dir = (uv - 0.5) * uC.w * 0.012;
    c = vec3(tap(uv + dir).r, c.g, tap(uv - dir).b);
  }

  // Motion blur.
  float motion = uE.z;
  if (motion > 0.001) {
    vec2 d = vec2(cos(uE.w), sin(uE.w)) * off(60.0 * motion);
    vec3 acc = vec3(0.0);
    for (int i = 0; i < 16; i++) {
      float t = (float(i) + 0.5) / 16.0 - 0.5;
      acc += tap(uv + d * t);
    }
    c = acc / 16.0;
  }

  // Lens blur: radial or linear focus area.
  if (uD.x > 0.001) {
    vec2 q = (uv - uE.xy) * 2.0;
    float dist = uD.w > 0.5 ? abs(q.y) : length(q);
    float inner = 0.15 + 0.6 * uD.y;
    float feather = 0.15 + 0.85 * uD.z;
    float mask = smoothstep(inner, inner + feather, dist);
    vec3 lb = disk(uv, off(40.0 * uD.x * mask));
    c = motion > 0.001 ? mix(c, lb, 0.5) : lb;
  }

  // Denoise / smooth (edge preserving).
  if (uC.y > 0.001) {
    c = mix(c, bilateral(uv, c, 1.5, 0.006), clamp(uC.y, 0.0, 1.0));
  }
  if (uC.x > 0.001) {
    c = mix(c, bilateral(uv, c, 4.0, 0.03), clamp(uC.x, 0.0, 1.0));
  }

  // Portrait: skin smoothing, face light, eye clarity.
  float skinSmooth = uF.x;
  float faceLight = uF.y;
  float eyeB = uF.z;
  if (skinSmooth > 0.001 || faceLight > 0.001 || eyeB > 0.001) {
    float cb = -0.169 * c.r - 0.331 * c.g + 0.5 * c.b;
    float cr = 0.5 * c.r - 0.419 * c.g - 0.081 * c.b;
    float skin = smoothstep(-0.17, -0.12, cb) * (1.0 - smoothstep(-0.02, 0.03, cb)) *
                 smoothstep(0.0, 0.04, cr) * (1.0 - smoothstep(0.16, 0.22, cr));
    float fm = 1.0;
    if (uFace.z > 0.0) {
      vec2 qf = (uv - uFace.xy) / uFace.zw;
      fm = 1.0 - smoothstep(0.75, 1.25, length(qf));
    }
    float m = skin * fm;
    if (skinSmooth > 0.001) {
      vec3 sm = bilateral(uv, c, 3.5, 0.02);
      c = mix(c, sm, clamp(skinSmooth * m * 1.2, 0.0, 1.0));
    }
    c *= 1.0 + faceLight * 0.35 * m;
    if (eyeB > 0.001) {
      float r = max(uF.w, 0.001);
      float e1 = 1.0 - smoothstep(0.0, r, length((uv - uEyes.xy) * vec2(aspect, 1.0)));
      float e2 = 1.0 - smoothstep(0.0, r, length((uv - uEyes.zw) * vec2(aspect, 1.0)));
      float e = max(e1, e2);
      c += e * eyeB * 0.25;
      c = mix(c, c * c * (3.0 - 2.0 * c), clamp(e * eyeB * 0.5, 0.0, 1.0));
    }
  }

  // Sharpening, deblur, texture.
  if (uA.x > 0.001) {
    vec2 o = off(1.0);
    vec3 b = (tap(uv + vec2(o.x, 0.0)) + tap(uv - vec2(o.x, 0.0)) +
              tap(uv + vec2(0.0, o.y)) + tap(uv - vec2(0.0, o.y))) * 0.25;
    c += (c - b) * uA.x * 2.0;
  }
  if (uC.z > 0.001) {
    c += (c - ring(uv, 2.5)) * uC.z * 1.8;
  }
  if (abs(uA.w) > 0.001) {
    c += (c - ring(uv, 3.0)) * uA.w * 1.4;
  }

  // Structure, clarity, ambiance (mid radius local contrast).
  float amb = uG.x;
  if (abs(uA.y) > 0.001 || abs(uA.z) > 0.001 || abs(amb) > 0.001) {
    vec3 bm = wide(uv, 8.0);
    float lm = luma(c);
    float midMask = 1.0 - abs(lm * 2.0 - 1.0);
    c += (c - bm) * uA.y * 1.5;
    c += (c - bm) * uA.z * 1.2 * (0.35 + 0.65 * midMask);
    c += (c - bm) * amb * 0.8;
  }

  // Dehaze and tonal contrast (large radius).
  if (abs(uB.x) > 0.001 || abs(uB.y) > 0.001 || abs(uB.z) > 0.001 || abs(uB.w) > 0.001) {
    vec3 bl = wide(uv, 28.0);
    if (uB.x > 0.001) {
      float dark = min(bl.r, min(bl.g, bl.b));
      float t = clamp(1.0 - uB.x * dark / 0.9, 0.25, 1.0);
      c = (c - 0.9) / t + 0.9;
      float g = luma(c);
      c = mix(vec3(g), c, 1.0 + uB.x * 0.2);
    } else if (uB.x < -0.001) {
      c = mix(c, vec3(0.85, 0.87, 0.9), -uB.x * 0.35);
    }
    float l = luma(c);
    float wLow = 1.0 - smoothstep(0.0, 0.5, l);
    float wHigh = smoothstep(0.5, 1.0, l);
    float wMid = clamp(1.0 - wLow - wHigh, 0.0, 1.0);
    c += (c - bl) * (uB.y * wLow + uB.z * wMid + uB.w * wHigh) * 1.6;
  }

  fragColor = vec4(clamp(c, 0.0, 1.0), 1.0);
}
