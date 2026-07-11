float hash(vec2 p) {
  vec3 q = fract(vec3(p.xyx) * 0.1031);
  q += dot(q, q.yzx + 33.33);
  return fract((q.x + q.y) * q.z);
}

float valueNoise(vec2 p) {
  vec2 i = floor(p);
  vec2 f = smoothstep(vec2(0.0), vec2(1.0), fract(p));
  float a = hash(i);
  float b = hash(i + vec2(1.0, 0.0));
  float c = hash(i + vec2(0.0, 1.0));
  float d = hash(i + vec2(1.0, 1.0));
  return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
  vec2 uv = fragCoord / max(iResolution.xy, vec2(1.0));
  float n = 0.0;
  float amp = 0.5;
  vec2 p = uv * 5.0 + vec2(iTime * 0.12, -iTime * 0.07);
  for (int octave = 0; octave < 5; ++octave) {
    n += valueNoise(p) * amp;
    p *= 2.03;
    amp *= 0.5;
  }
  vec3 cold = vec3(0.05, 0.12, 0.20);
  vec3 warm = vec3(0.95, 0.72, 0.32);
  fragColor = vec4(mix(cold, warm, smoothstep(0.15, 0.85, n)), 1.0);
}
