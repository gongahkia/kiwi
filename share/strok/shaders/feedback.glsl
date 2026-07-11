float ring(vec2 p, float radius) {
  return smoothstep(0.03, 0.0, abs(length(p) - radius));
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
  vec2 uv = fragCoord / max(iResolution.xy, vec2(1.0));
  vec2 p = uv * 2.0 - 1.0;
  p.x *= iResolution.x / max(iResolution.y, 1.0);

  vec2 wobble = 0.006 * vec2(sin(iTime + p.y * 9.0), cos(iTime * 0.8 + p.x * 8.0));
  vec3 previous = texture(iChannel0, clamp(uv + wobble, vec2(0.0), vec2(1.0))).rgb * 0.965;
  float pulse = ring(p, 0.22 + 0.08 * sin(iTime * 1.7));
  float sweep = smoothstep(0.015, 0.0, abs(p.y - 0.45 * sin(iTime + p.x * 3.0)));
  vec3 ink = vec3(0.2, 0.9, 0.7) * pulse + vec3(1.0, 0.45, 0.15) * sweep;
  fragColor = vec4(max(previous, ink), 1.0);
}
