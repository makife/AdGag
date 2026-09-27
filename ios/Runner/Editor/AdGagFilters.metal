// Core Image Metal kernels for the editor's look effects — a line-for-line
// port of the GLSL shaders in android/.../editor/VideoFilters.kt, so an
// effect looks the same on both platforms. Built with the Core Image
// Metal flags (-fcikernel / -cikernel, set on the Runner target) and loaded
// from default.metallib by AdGagRenderer.
//
// Conventions (same as the GLSL): uv in 0..1 with y UP (Core Image is y-up
// too); p = (uv.x * aspect, uv.y) measures in frame heights so shapes stay
// round. Every kernel has the same signature:
//   (sampler src, float2 size, float time, destination dest)

#include <metal_stdlib>
#include <CoreImage/CoreImage.h>
using namespace metal;

namespace adgag {
  inline float rand(float2 co) { return fract(sin(dot(co, float2(12.9898, 78.233))) * 43758.5453); }
  inline float luma(float3 c) { return dot(c, float3(0.299, 0.587, 0.114)); }
  inline float3 sepia(float3 c) {
    return clamp(float3(dot(c, float3(0.393, 0.769, 0.189)), dot(c, float3(0.349, 0.686, 0.168)),
                        dot(c, float3(0.272, 0.534, 0.131))), float3(0.0), float3(1.0));
  }
  inline float vignette(float2 uv, float amount) {
    return 1.0 - smoothstep(0.35, 0.85, distance(uv, float2(0.5))) * amount;
  }
  inline float4 tex(coreimage::sampler src, float2 size, float2 uv) {
    return src.sample(src.transform(clamp(uv, float2(0.0), float2(1.0)) * size));
  }
  inline float hash(float2 c) { return rand(floor(c * 1000.0 + 0.5)); }
  inline float3 palette(float h) {
    if (h < 0.25) return float3(0.95, 0.25, 0.35);
    if (h < 0.5) return float3(0.25, 0.6, 0.95);
    if (h < 0.75) return float3(1.0, 0.8, 0.2);
    return float3(0.6, 0.35, 0.95);
  }
  // Evenly spaced points around the inset rectangle, corners shared.
  inline float2 borderPoint(float2 p, float spacing, float inset, float aspect) {
    float w = aspect - 2.0 * inset;
    float h = 1.0 - 2.0 * inset;
    float nx = max(1.0, floor(w / spacing + 0.5));
    float ny = max(1.0, floor(h / spacing + 0.5));
    float sx = w / nx;
    float sy = h / ny;
    float kx = clamp(floor((p.x - inset) / sx + 0.5), 0.0, nx);
    float ky = clamp(floor((p.y - inset) / sy + 0.5), 0.0, ny);
    float2 c = float2(inset + kx * sx, inset);
    float d = distance(p, c);
    float2 c2 = float2(aspect - inset, inset + ky * sy);
    if (distance(p, c2) < d) { c = c2; d = distance(p, c2); }
    float2 c3 = float2(inset + kx * sx, 1.0 - inset);
    if (distance(p, c3) < d) { c = c3; d = distance(p, c3); }
    float2 c4 = float2(inset, inset + ky * sy);
    if (distance(p, c4) < d) { c = c4; }
    return c;
  }
}

extern "C" {
namespace coreimage {

float4 adgag_bw(sampler src, float2 size, float time, destination dest) {
  float2 vUv = dest.coord() / size;
  float4 c = adgag::tex(src, size, vUv);
  return float4(float3(adgag::luma(c.rgb)), c.a);
}

float4 adgag_sepia(sampler src, float2 size, float time, destination dest) {
  float2 vUv = dest.coord() / size;
  float4 c = adgag::tex(src, size, vUv);
  return float4(adgag::sepia(c.rgb), c.a);
}

float4 adgag_vintage(sampler src, float2 size, float time, destination dest) {
  float2 vUv = dest.coord() / size;
  float4 c = adgag::tex(src, size, vUv);
  float3 col = mix(c.rgb, adgag::sepia(c.rgb), float3(0.6));
  col = col * 0.82 + 0.1;
  col *= adgag::vignette(vUv, 0.6);
  return float4(clamp(col, float3(0.0), float3(1.0)), c.a);
}

float4 adgag_cool(sampler src, float2 size, float time, destination dest) {
  float4 c = adgag::tex(src, size, dest.coord() / size);
  return float4(clamp(c.rgb * float3(0.88, 1.0, 1.18), float3(0.0), float3(1.0)), c.a);
}

float4 adgag_warm(sampler src, float2 size, float time, destination dest) {
  float4 c = adgag::tex(src, size, dest.coord() / size);
  return float4(clamp(c.rgb * float3(1.15, 1.02, 0.84), float3(0.0), float3(1.0)), c.a);
}

float4 adgag_vivid(sampler src, float2 size, float time, destination dest) {
  float4 c = adgag::tex(src, size, dest.coord() / size);
  float l = adgag::luma(c.rgb);
  return float4(clamp(mix(float3(l), c.rgb, float3(1.7)), float3(0.0), float3(1.0)), c.a);
}

float4 adgag_invert(sampler src, float2 size, float time, destination dest) {
  float4 c = adgag::tex(src, size, dest.coord() / size);
  return float4(1.0 - c.rgb, c.a);
}

float4 adgag_fisheye(sampler src, float2 size, float time, destination dest) {
  float aspect = size.x / size.y;
  float2 vUv = dest.coord() / size;
  float2 p = vUv * 2.0 - 1.0;
  p.x *= aspect;
  float maxR = length(float2(aspect, 1.0));
  float rn = length(p) / maxR;
  float2 q = p * (0.55 + 0.45 * rn * rn);
  q.x /= aspect;
  float4 c = adgag::tex(src, size, q * 0.5 + 0.5);
  float edge = 1.0 - smoothstep(0.82, 1.0, rn);
  return float4(c.rgb * edge, c.a);
}

float4 adgag_old_tv(sampler src, float2 size, float time, destination dest) {
  float2 vUv = dest.coord() / size;
  float4 c = adgag::tex(src, size, vUv);
  float3 col = float3(adgag::luma(c.rgb)) * 1.1;
  col *= 0.8 + 0.2 * sin(vUv.y * 1400.0);
  float n = adgag::rand(vUv * 500.0 + time);
  col += (n - 0.5) * 0.18;
  col *= 0.94 + 0.06 * sin(time * 50.0);
  col *= adgag::vignette(vUv, 0.8);
  return float4(clamp(col, float3(0.0), float3(1.0)), c.a);
}

float4 adgag_static(sampler src, float2 size, float time, destination dest) {
  float2 vUv = dest.coord() / size;
  float4 c = adgag::tex(src, size, vUv);
  float n = adgag::rand(floor(vUv * float2(270.0, 480.0)) + fract(time * 13.0) * 100.0);
  float band = step(0.93, adgag::rand(float2(floor(vUv.y * 40.0), floor(time * 12.0))));
  float3 col = mix(c.rgb, float3(n), float3(0.45 + 0.3 * band));
  return float4(col, c.a);
}

float4 adgag_vhs(sampler src, float2 size, float time, destination dest) {
  float2 vUv = dest.coord() / size;
  float line = floor(vUv.y * 90.0);
  float t = floor(time * 10.0);
  float jump = step(0.95, adgag::rand(float2(line, t)));
  float2 uv = vUv + float2((adgag::rand(float2(t, line)) - 0.5) * 0.04 * jump, 0.0);
  float off = 0.005;
  float4 c = adgag::tex(src, size, uv);
  float3 col = float3(adgag::tex(src, size, uv + float2(off, 0.0)).r, c.g,
                      adgag::tex(src, size, uv - float2(off, 0.0)).b);
  col *= 0.93 + 0.07 * sin(vUv.y * 900.0);
  col += (adgag::rand(vUv * 300.0 + time) - 0.5) * 0.08;
  return float4(clamp(col, float3(0.0), float3(1.0)), c.a);
}

float4 adgag_glitch(sampler src, float2 size, float time, destination dest) {
  float2 vUv = dest.coord() / size;
  float t = floor(time * 8.0);
  float on = step(0.55, adgag::rand(float2(t, 3.0)));
  float shift = (adgag::rand(float2(floor(vUv.y * 18.0), t)) - 0.5) * 0.12 * on;
  float2 uv = vUv + float2(shift, 0.0);
  float split = 0.012 + 0.02 * on;
  float4 c = adgag::tex(src, size, uv);
  float3 col = float3(adgag::tex(src, size, uv + float2(split, 0.0)).r, c.g,
                      adgag::tex(src, size, uv - float2(split, 0.0)).b);
  return float4(col, c.a);
}

float4 adgag_pixelate(sampler src, float2 size, float time, destination dest) {
  float aspect = size.x / size.y;
  float2 vUv = dest.coord() / size;
  float2 cells = float2(36.0, 36.0 / aspect);
  float2 uv = (floor(vUv * cells) + 0.5) / cells;
  return adgag::tex(src, size, uv);
}

float4 adgag_mirror(sampler src, float2 size, float time, destination dest) {
  float2 vUv = dest.coord() / size;
  float2 uv = float2(vUv.x < 0.5 ? vUv.x : 1.0 - vUv.x, vUv.y);
  return adgag::tex(src, size, uv);
}

float4 adgag_flowers(sampler src, float2 size, float time, destination dest) {
  float aspect = size.x / size.y;
  float2 vUv = dest.coord() / size;
  float4 c = adgag::tex(src, size, vUv);
  float2 p = float2(vUv.x * aspect, vUv.y);
  float2 bp = adgag::borderPoint(p, 0.11, 0.055, aspect);
  float2 d = p - bp;
  float r = length(d);
  float a = atan2(d.y, d.x);
  float petal = 0.05 * (0.45 + 0.55 * (0.5 + 0.5 * cos(5.0 * a)));
  float3 petalColor = adgag::hash(bp) < 0.5 ? float3(1.0, 0.55, 0.75) : float3(1.0, 0.95, 0.97);
  float3 col = c.rgb;
  if (r < petal) col = petalColor;
  if (r < 0.014) col = float3(1.0, 0.82, 0.25);
  return float4(col, c.a);
}

float4 adgag_hearts(sampler src, float2 size, float time, destination dest) {
  float aspect = size.x / size.y;
  float2 vUv = dest.coord() / size;
  float4 c = adgag::tex(src, size, vUv);
  float2 p = float2(vUv.x * aspect, vUv.y);
  float2 bp = adgag::borderPoint(p, 0.1, 0.05, aspect);
  float2 q = (p - bp) / 0.035;
  float k = q.x * q.x + q.y * q.y - 1.0;
  float h = k * k * k - q.x * q.x * q.y * q.y * q.y;
  float3 col = c.rgb;
  if (h <= 0.0) col = adgag::hash(bp) < 0.5 ? float3(0.95, 0.15, 0.35) : float3(1.0, 0.45, 0.6);
  return float4(col, c.a);
}

float4 adgag_film(sampler src, float2 size, float time, destination dest) {
  float aspect = size.x / size.y;
  float2 vUv = dest.coord() / size;
  float4 c = adgag::tex(src, size, vUv);
  float2 p = float2(vUv.x * aspect, vUv.y);
  float3 col = mix(c.rgb, adgag::sepia(c.rgb), float3(0.35));
  float bar = 0.075;
  float fromEdge = min(p.x, aspect - p.x);
  if (fromEdge < bar) {
    col = float3(0.05);
    float hy = abs(fract(p.y / 0.055) - 0.5);
    float hx = abs(fromEdge - bar * 0.5);
    if (hy < 0.2 && hx < bar * 0.22) col = float3(0.92);
  }
  return float4(col, c.a);
}

float4 adgag_ivy(sampler src, float2 size, float time, destination dest) {
  float aspect = size.x / size.y;
  float2 vUv = dest.coord() / size;
  float4 c = adgag::tex(src, size, vUv);
  float2 p = float2(vUv.x * aspect, vUv.y);
  float inset = 0.045;
  float3 col = c.rgb;
  float2 rel = abs(p - float2(aspect * 0.5, 0.5)) - float2(aspect * 0.5 - inset, 0.5 - inset);
  float sd = max(rel.x, rel.y);
  float wave = 0.006 * sin((p.x + p.y) * 70.0);
  if (abs(sd - wave) < 0.0035) col = float3(0.2, 0.42, 0.16);
  float2 bp = adgag::borderPoint(p, 0.06, inset, aspect);
  float2 q = p - bp;
  float side = adgag::hash(bp) < 0.5 ? 1.0 : -1.0;
  bool horizontal = abs(bp.y - inset) < 0.001 || abs(bp.y - (1.0 - inset)) < 0.001;
  float2 lq = horizontal ? float2(q.x, q.y - side * 0.018) : float2(q.x - side * 0.018, q.y);
  float2 rad = horizontal ? float2(0.011, 0.02) : float2(0.02, 0.011);
  float2 e = lq / rad;
  if (dot(e, e) < 1.0) col = mix(float3(0.16, 0.45, 0.14), float3(0.45, 0.75, 0.25), float3(adgag::hash(bp + 0.5)));
  return float4(col, c.a);
}

float4 adgag_balloons(sampler src, float2 size, float time, destination dest) {
  float aspect = size.x / size.y;
  float2 vUv = dest.coord() / size;
  float4 c = adgag::tex(src, size, vUv);
  float2 p = float2(vUv.x * aspect, vUv.y);
  float2 bp = adgag::borderPoint(p, 0.14, 0.07, aspect);
  float2 q = p - bp;
  float3 bcol = adgag::palette(adgag::hash(bp));
  float3 col = c.rgb;
  if (abs(q.x + 0.004 * sin(q.y * 120.0)) < 0.0018 && q.y < -0.04 && q.y > -0.068) col = float3(0.95);
  float2 knot = (q - float2(0.0, -0.05)) / 0.006;
  if (dot(knot, knot) < 1.0) col = bcol * 0.8;
  float2 e = q / float2(0.038, 0.048);
  if (dot(e, e) < 1.0) {
    col = bcol;
    float2 hl = (q - float2(-0.012, 0.018)) / float2(0.008, 0.013);
    if (dot(hl, hl) < 1.0) col = mix(bcol, float3(1.0), float3(0.6));
  }
  return float4(col, c.a);
}

float4 adgag_stars(sampler src, float2 size, float time, destination dest) {
  float aspect = size.x / size.y;
  float2 vUv = dest.coord() / size;
  float4 c = adgag::tex(src, size, vUv);
  float2 p = float2(vUv.x * aspect, vUv.y);
  float2 bp = adgag::borderPoint(p, 0.1, 0.05, aspect);
  float2 q = p - bp;
  float r = length(q);
  float a = atan2(q.y, q.x) - 1.5708;
  float spike = pow(0.5 + 0.5 * cos(5.0 * a), 3.0);
  float radius = 0.036 * (0.42 + 0.58 * spike);
  float h = adgag::hash(bp);
  float twinkle = 0.75 + 0.25 * sin(time * 6.0 + h * 6.283);
  float3 col = c.rgb;
  if (r < radius) col = mix(float3(1.0, 0.85, 0.3), float3(1.0), float3(h < 0.5 ? 0.0 : 0.7)) * twinkle;
  return float4(col, c.a);
}

float4 adgag_confetti(sampler src, float2 size, float time, destination dest) {
  float aspect = size.x / size.y;
  float2 vUv = dest.coord() / size;
  float4 c = adgag::tex(src, size, vUv);
  float2 p = float2(vUv.x * aspect, vUv.y);
  float2 cell = floor(p / 0.045);
  float h1 = adgag::rand(cell);
  float h2 = adgag::rand(cell + 17.0);
  float h3 = adgag::rand(cell + 41.0);
  float2 center = (cell + float2(0.2 + 0.6 * h1, 0.2 + 0.6 * h2)) * 0.045;
  float edgeDist = min(min(center.x, aspect - center.x), min(center.y, 1.0 - center.y));
  float3 col = c.rgb;
  if (edgeDist < 0.11 && h3 < 0.7) {
    float2 q = p - center;
    float ang = h1 * 6.283 + time * 2.0 * (h2 - 0.5);
    float2 rq = float2(cos(ang) * q.x - sin(ang) * q.y, sin(ang) * q.x + cos(ang) * q.y);
    if (abs(rq.x) < 0.008 && abs(rq.y) < 0.004) col = adgag::palette(h3 / 0.7);
  }
  return float4(col, c.a);
}

} // namespace coreimage
} // extern "C"
