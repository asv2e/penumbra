#version 460 core
precision highp float;

#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;
uniform vec4 uA;     // brightness, contrast, saturation, ambiance
uniform vec4 uB;     // highlights, shadows, warmth, blacks
uniform vec4 uC;     // whites, wbTemp, wbTint, vibrance
uniform vec4 uD;     // hueShift, stShadowHue, stShadowAmt, stHighHue
uniform vec4 uE;     // stHighAmt, curvesOn, hslOn, monoOn
uniform vec4 uMono;  // r, g, b weights, bwBright
uniform vec4 uF;     // bwContrast
uniform vec4 uH0;    // hsl hue  red..yellow? (bands 0-3)
uniform vec4 uH1;    // hsl hue  bands 4-7
uniform vec4 uS0;
uniform vec4 uS1;
uniform vec4 uL0;
uniform vec4 uL1;
uniform vec4 uP0;    // selective point: x, y, radius, active
uniform vec4 uQ0;    // brightness, contrast, saturation, warmth
uniform vec4 uP1;
uniform vec4 uQ1;
uniform vec4 uP2;
uniform vec4 uQ2;
uniform vec4 uP3;
uniform vec4 uQ3;
uniform sampler2D uImage;
uniform sampler2D uLut;

out vec4 fragColor;

vec3 tap(vec2 uv) {
  return texture(uImage, clamp(uv, vec2(0.0), vec2(1.0))).rgb;
}

float luma(vec3 c) {
  return dot(c, vec3(0.299, 0.587, 0.114));
}

vec3 rgb2hsv(vec3 c) {
  vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
  vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
  vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
  float d = q.x - min(q.w, q.y);
  float e = 1.0e-10;
  return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

vec3 hsv2rgb(vec3 c) {
  vec4 K = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
  vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
  return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}

float bandW(float h, float center, float width) {
  float d = abs(h - center);
  d = min(d, 1.0 - d);
  return max(0.0, 1.0 - d / width);
}

vec3 selective(vec3 c, vec3 orig, vec2 uv, vec4 P, vec4 Q) {
  if (P.w < 0.5) return c;
  float aspect = uSize.x / uSize.y;
  float d = length((uv - P.xy) * vec2(aspect, 1.0));
  float spatial = 1.0 - smoothstep(P.z * 0.35, P.z, d);
  if (spatial <= 0.0) return c;
  vec3 ref = tap(P.xy);
  vec3 e = orig - ref;
  float sim = exp(-dot(e, e) / 0.06);
  float w = spatial * sim;
  c += Q.x * 0.4 * w;
  c = (c - 0.5) * (1.0 + Q.y * 0.9 * w) + 0.5;
  float g = luma(c);
  c = mix(vec3(g), c, max(0.0, 1.0 + Q.z * w));
  c.r += Q.w * 0.12 * w;
  c.b -= Q.w * 0.12 * w;
  return c;
}

void main() {
  vec2 uv = FlutterFragCoord().xy / uSize;
  vec3 orig = tap(uv);
  vec3 c = orig;

  // White balance and warmth.
  float temp = uC.y;
  float tint = uC.z;
  c.r *= 1.0 + 0.30 * temp + 0.06 * tint;
  c.b *= 1.0 - 0.30 * temp + 0.06 * tint;
  c.g *= 1.0 - 0.20 * tint;
  c.r += uB.z * 0.10;
  c.b -= uB.z * 0.10;

  // Exposure and tonal ranges.
  c += uA.x * 0.4;
  float l = luma(c);
  c += uB.w * 0.15 * (1.0 - smoothstep(0.0, 0.4, l));
  c += uC.x * 0.15 * smoothstep(0.6, 1.0, l);
  c += uB.y * 0.35 * (1.0 - smoothstep(0.0, 0.55, l));
  c += uB.x * 0.35 * smoothstep(0.45, 1.0, l);
  c = (c - 0.5) * (1.0 + uA.y * 0.9) + 0.5;
  c += uA.w * 0.12 * (1.0 - smoothstep(0.0, 0.6, luma(c)));

  // Vibrance and saturation.
  float g = luma(c);
  float sat = max(c.r, max(c.g, c.b)) - min(c.r, min(c.g, c.b));
  c = mix(vec3(g), c, max(0.0, 1.0 + uA.z + uA.w * 0.25 + uC.w * (1.0 - clamp(sat, 0.0, 1.0))));

  // HSL per colour band + global hue shift.
  if (uE.z > 0.5 || abs(uD.x) > 0.001) {
    vec3 hsv = rgb2hsv(clamp(c, 0.0, 1.0));
    float h = hsv.x;
    float w0 = bandW(h, 0.0, 0.085);
    float w1 = bandW(h, 0.083, 0.07);
    float w2 = bandW(h, 0.167, 0.09);
    float w3 = bandW(h, 0.333, 0.14);
    float w4 = bandW(h, 0.5, 0.12);
    float w5 = bandW(h, 0.611, 0.12);
    float w6 = bandW(h, 0.75, 0.10);
    float w7 = bandW(h, 0.875, 0.10);
    float sm = smoothstep(0.03, 0.2, hsv.y);
    float dh = w0 * uH0.x + w1 * uH0.y + w2 * uH0.z + w3 * uH0.w +
               w4 * uH1.x + w5 * uH1.y + w6 * uH1.z + w7 * uH1.w;
    float ds = w0 * uS0.x + w1 * uS0.y + w2 * uS0.z + w3 * uS0.w +
               w4 * uS1.x + w5 * uS1.y + w6 * uS1.z + w7 * uS1.w;
    float dl = w0 * uL0.x + w1 * uL0.y + w2 * uL0.z + w3 * uL0.w +
               w4 * uL1.x + w5 * uL1.y + w6 * uL1.z + w7 * uL1.w;
    hsv.x = fract(h + dh * 0.08 * sm + uD.x * 0.25);
    hsv.y = clamp(hsv.y * (1.0 + ds), 0.0, 1.0);
    hsv.z = clamp(hsv.z + dl * 0.25 * sm, 0.0, 1.0);
    c = hsv2rgb(hsv);
  }

  // Selective control points.
  c = selective(c, orig, uv, uP0, uQ0);
  c = selective(c, orig, uv, uP1, uQ1);
  c = selective(c, orig, uv, uP2, uQ2);
  c = selective(c, orig, uv, uP3, uQ3);

  // Curves (LUT: R/G/B channels each hold that channel's curve).
  if (uE.y > 0.5) {
    vec3 cc = clamp(c, 0.0, 1.0);
    float kx = 255.0 / 256.0;
    float ko = 0.5 / 256.0;
    c = vec3(texture(uLut, vec2(cc.r * kx + ko, 0.5)).r,
             texture(uLut, vec2(cc.g * kx + ko, 0.5)).g,
             texture(uLut, vec2(cc.b * kx + ko, 0.5)).b);
  }

  // Black & white with channel filter.
  if (uE.w > 0.5) {
    float m = dot(clamp(c, 0.0, 1.0), uMono.rgb);
    m = (m - 0.5) * (1.0 + uF.x * 0.9) + 0.5 + uMono.w * 0.4;
    c = vec3(m);
  }

  // Split toning.
  float l2 = luma(c);
  if (uD.z > 0.001) {
    c += (hsv2rgb(vec3(uD.y, 0.8, 1.0)) - 0.5) * uD.z * 0.3 * (1.0 - smoothstep(0.1, 0.7, l2));
  }
  if (uE.x > 0.001) {
    c += (hsv2rgb(vec3(uD.w, 0.8, 1.0)) - 0.5) * uE.x * 0.3 * smoothstep(0.3, 0.9, l2);
  }

  fragColor = vec4(clamp(c, 0.0, 1.0), 1.0);
}
