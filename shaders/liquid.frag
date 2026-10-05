#version 460 core

// The Vessel's liquid. Painted full-screen; everything above the surface is
// left transparent so the ink background shows through.

#include <flutter/runtime_effect.glsl>

precision highp float;

uniform vec2 uSize;    // canvas size, logical pixels
uniform float uTime;   // seconds of wave phase, wrapped by the app
uniform float uFill;   // liquid height above the bottom edge, logical pixels
uniform float uLean;   // surface slope; positive is higher on the left
uniform float uSlosh;  // signed disturbance, 0 when calm
uniform vec3 uColor;   // the status band colour

out vec4 fragColor;

const float PI = 3.14159265;
const float IDLE_AMPLITUDE = 2.4;
const float SLOSH_AMPLITUDE = 7.0;
const float SLOSH_ROCK = 16.0;
const vec3 INK = vec3(0.055, 0.078, 0.125);

// Ripples at x: a few summed sines, larger while the surface is disturbed.
// Keep in step with LiquidMotion.ripple.
float ripple(float x, float phase) {
  float amplitude = IDLE_AMPLITUDE + abs(uSlosh) * SLOSH_AMPLITUDE;
  float t = uTime + phase;
  return amplitude * (0.55 * sin(x * 0.030 + t * 1.1)
                    + 0.30 * sin(x * 0.065 - t * 1.7)
                    + 0.15 * sin(x * 0.018 + t * 0.6));
}

// The lean and the rocking of the whole surface at x, positive downward.
// Keep in step with LiquidMotion.slope.
float slope(float x) {
  return uLean * (x - uSize.x * 0.5)
       + uSlosh * SLOSH_ROCK * cos(PI * x / uSize.x);
}

void main() {
  vec2 p = FlutterFragCoord().xy;
  float level = uSize.y - uFill;

  // Front surface, and a paler back wave a little higher and out of phase.
  float tilt = slope(p.x);
  float front = level + tilt + ripple(p.x, 0.0);
  float back = level - 5.0 + tilt + ripple(p.x + 140.0, 2.6) * 1.35;

  float inFront = smoothstep(-0.75, 0.75, p.y - front);
  float inBack = smoothstep(-0.75, 0.75, p.y - back);

  // Depth gradient: the band colour at the surface, darker toward the bottom.
  float depth = clamp((p.y - front) / max(uFill, 1.0), 0.0, 1.0);
  vec3 deep = mix(uColor, INK, 0.42);
  vec3 body = mix(uColor, deep, smoothstep(0.0, 1.0, depth));

  // A soft highlight just under the surface, and a thin bright crest.
  float under = max(p.y - front, 0.0);
  float glow = exp(-under / 22.0) * 0.07;
  float crest = exp(-under / 1.8) * 0.20;
  body += (glow + crest) * vec3(1.0);

  vec3 backColor = mix(INK, uColor, 0.45);

  // Front over back over nothing, premultiplied.
  float backAlpha = inBack * (1.0 - inFront);
  vec3 rgb = body * inFront + backColor * backAlpha;
  float alpha = inFront + backAlpha;
  fragColor = vec4(rgb, alpha);
}
