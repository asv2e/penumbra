#version 460 core
precision highp float;

#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;
uniform vec4 uA;   // bloom, bloomThr, bloomRad, glow
uniform vec4 uB;   // glowSat, glowWarm, halation, halThr
uniform vec4 uC;   // halRad, hdr, hdrBright, hdrSat
uniform vec4 uD;   // drama, dramaSat, grungeTex, grungeContrast
uniform vec4 uE;   // grungeSat, grungeStyle, leaks, scratches
uniform vec4 uF;   // retroStyle, fade, grain, grainSize
uniform vec4 uG;   // vignette, vigSize, vigFeather, unused
uniform vec4 uH;   // vigCx, vigCy, seed, unused
uniform sampler2D uImage;

out vec4 fragColor;

vec3 tap(vec2 uv) {
  return texture(uImage, clamp(uv, vec2(0.0), vec2(1.0))).rgb;
}

vec2 off(float px) {
  float x = px / 1280.0;
  return vec2(x, x * uSize.x / uSize.y);
}

float luma(vec3 c) {
  return dot(c, vec3(0.299, 0.587, 0.114));
}

float hash(vec2 p) {
  return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
  vec2 i = floor(p);
  vec2 f = fract(p);
  f = f * f * (3.0 - 2.0 * f);
  float a = hash(i);
  float b = hash(i + vec2(1.0, 0.0));
  float c = hash(i + vec2(0.0, 1.0));
  float d = hash(i + vec2(1.0, 1.0));
  return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p) {
  float v = 0.0;
  float a = 0.5;
  for (int i = 0; i < 4; i++) {
    v += a * vnoise(p);
    p *= 2.03;
    a *= 0.5;
  }
  return v;
}

vec3 screen(vec3 a, vec3 b) {
  return 1.0 - (1.0 - a) * (1.0 - b);
}

vec3 overlayBlend(vec3 base, vec3 top) {
  return mix(2.0 * base * top, 1.0 - 2.0 * (1.0 - base) * (1.0 - top), step(0.5, base));
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

// Average of bright pixels around uv (used by bloom and halation).
vec3 brightDisk(vec2 uv, float px, float thr) {
  vec3 acc = vec3(0.0);
  vec2 r = off(px);
  for (int i = 0; i < 16; i++) {
    float fi = float(i);
    float a = fi * 2.3999632;
    float rad = sqrt((fi + 0.5) / 16.0);
    vec3 s = tap(uv + vec2(cos(a), sin(a)) * rad * r);
    acc += s * smoothstep(thr, thr + 0.25, luma(s));
  }
  return acc / 16.0;
}

void main() {
  vec2 uv = FlutterFragCoord().xy / uSize;
  float aspect = uSize.x / uSize.y;
  vec3 c = tap(uv);

  // HDR Scape: multi-scale local contrast with tone compression.
  if (uC.y > 0.001) {
    vec3 bm = wide(uv, 9.0);
    vec3 bl = wide(uv, 30.0);
    float k = uC.y;
    c += (c - bm) * k * 1.4 + (c - bl) * k * 0.8;
    c = c / (1.0 + k * 0.25 * c) * (1.0 + k * 0.25);
    c += uC.z * 0.3;
    float g = luma(c);
    c = mix(vec3(g), c, max(0.0, 1.0 + uC.w + k * 0.25));
  }

  // Drama.
  if (uD.x > 0.001) {
    vec3 bl = wide(uv, 24.0);
    float k = uD.x;
    c += (c - bl) * k * 1.6;
    c = (c - 0.5) * (1.0 + k * 0.4) + 0.5;
    float g = luma(c);
    c = mix(vec3(g), c, max(0.0, 1.0 - k * 0.35 + uD.y));
  }

  // Bloom.
  if (uA.x > 0.001) {
    vec3 b = brightDisk(uv, 8.0 + 40.0 * uA.z, 0.4 + 0.5 * uA.y);
    c = screen(c, b * uA.x * 1.6);
  }

  // Glow (glamour glow).
  if (uA.w > 0.001) {
    vec3 acc = vec3(0.0);
    vec2 r = off(22.0);
    for (int i = 0; i < 16; i++) {
      float fi = float(i);
      float a = fi * 2.3999632;
      float rad = sqrt((fi + 0.5) / 16.0);
      acc += tap(uv + vec2(cos(a), sin(a)) * rad * r);
    }
    vec3 gl = acc / 16.0;
    gl = mix(vec3(luma(gl)), gl, max(0.0, 1.0 + uB.x));
    gl.r += uB.y * 0.1;
    gl.b -= uB.y * 0.1;
    c = mix(c, screen(c, gl), clamp(uA.w, 0.0, 1.0));
  }

  // Halation: red/orange halo around highlights.
  if (uB.z > 0.001) {
    vec3 h = brightDisk(uv, 20.0 + 60.0 * uC.x, 0.55 + 0.4 * uB.w);
    c += h * vec3(1.0, 0.32, 0.12) * uB.z * 1.8;
  }

  // Grunge texture overlay.
  if (uD.z > 0.001 && uE.y > 0.5) {
    float st = uE.y;
    vec2 p = uv * vec2(aspect, 1.0);
    float t;
    vec3 tint;
    if (st < 1.5) {
      t = fbm(p * 4.0) * 0.6 + fbm(p * 18.0) * 0.4;
      tint = vec3(0.90, 0.86, 0.82);
    } else if (st < 2.5) {
      t = fbm(p * 9.0 + 3.0) * 0.5 + 0.5 * vnoise(p * 60.0);
      tint = vec3(1.0, 0.93, 0.80);
    } else if (st < 3.5) {
      t = fbm(vec2(p.x * 40.0, p.y * 2.0));
      tint = vec3(0.85, 0.90, 1.0);
    } else if (st < 4.5) {
      t = clamp(pow(fbm(p * 6.0), 2.0) * 1.6, 0.0, 1.0);
      tint = vec3(1.0, 0.85, 0.70);
    } else {
      t = fbm(p * 30.0);
      tint = vec3(0.95);
    }
    t = clamp((t - 0.5) * (1.0 + uD.w * 1.5) + 0.5, 0.0, 1.0);
    vec3 tex = vec3(t) * tint;
    c = mix(c, overlayBlend(clamp(c, 0.0, 1.0), tex), clamp(uD.z, 0.0, 1.0));
    float g = luma(c);
    c = mix(vec3(g), c, max(0.0, 1.0 + uE.x));
  }

  // Retrolux light leaks and scratches.
  if (uE.z > 0.001) {
    float st = max(uF.x, 1.0);
    vec3 col = st < 1.5 ? vec3(1.0, 0.45, 0.15)
             : st < 2.5 ? vec3(1.0, 0.70, 0.20)
             : st < 3.5 ? vec3(0.90, 0.30, 0.50)
             : st < 4.5 ? vec3(0.30, 0.60, 1.00)
             : vec3(1.0, 0.50, 0.30);
    float edge = pow(clamp(abs(uv.x - 0.5) * 2.0, 0.0, 1.0), 2.5);
    float blob = fbm(uv * 2.2 + vec2(uH.z, uH.z * 2.0));
    float leak = clamp((blob - 0.35) * 2.5, 0.0, 1.0) * edge;
    float corner = pow(1.0 - clamp(length(uv - vec2(1.0, 0.0)), 0.0, 1.0), 2.0);
    leak = max(leak, corner * 0.8);
    c = screen(c, col * leak * uE.z);
  }
  if (uE.w > 0.001) {
    float colx = floor(uv.x * 900.0);
    float rnd = hash(vec2(colx, 7.0));
    float line = step(0.992, rnd) * smoothstep(0.45, 0.65, vnoise(vec2(uv.y * 5.0, colx)));
    float dust = step(0.9985, hash(floor(uv * vec2(aspect, 1.0) * 400.0) + 11.0));
    c = mix(c, vec3(0.95), clamp((line * 0.6 + dust * 0.8) * uE.w, 0.0, 1.0));
  }

  // Fade.
  c = c * (1.0 - uF.y * 0.2) + uF.y * 0.1;

  // Vignette (negative = light vignette).
  if (abs(uG.x) > 0.001) {
    vec2 q = (uv - uH.xy) * 2.0;
    float d = length(q) * 0.7071;
    float inner = 0.2 + 0.5 * uG.y;
    float fe = 0.2 + 0.8 * uG.z;
    float v = smoothstep(inner, inner + fe, d);
    if (uG.x > 0.0) {
      c *= 1.0 - uG.x * 0.85 * v;
    } else {
      c = mix(c, vec3(1.0), -uG.x * 0.7 * v);
    }
  }

  // Film grain.
  if (uF.z > 0.001) {
    vec2 gp = floor(uv * vec2(1280.0, 1280.0 / aspect) / (1.0 + uF.w * 3.0));
    float n = hash(gp + 3.1);
    c += (n - 0.5) * uF.z * 0.3;
  }

  fragColor = vec4(clamp(c, 0.0, 1.0), 1.0);
}
