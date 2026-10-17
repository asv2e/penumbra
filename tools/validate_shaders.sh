#!/usr/bin/env bash
# Compiles every fragment shader with glslangValidator (syntax and type check).
set -euo pipefail
command -v glslangValidator >/dev/null || { echo "glslangValidator not found (apt install glslang-tools)"; exit 1; }
tmp="$(mktemp -d)"
for f in shaders/*.frag; do
  out="$tmp/$(basename "$f")"
  sed 's|#include <flutter/runtime_effect.glsl>|vec2 FlutterFragCoord() { return gl_FragCoord.xy; }|' "$f" > "$out"
  echo "validating $f"
  glslangValidator -S frag "$out"
done
