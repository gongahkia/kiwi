void mainImage(out vec4 fragColor, in vec2 fragCoord) {
  vec2 uv = (fragCoord * 2.0 - iResolution.xy) / max(iResolution.y, 1.0);
  float t = iTime * 0.75;
  float field = 0.0;
  field += sin((uv.x + t) * 3.0);
  field += sin((uv.y - t * 0.7) * 4.0);
  field += sin((uv.x + uv.y + t * 0.35) * 5.0);
  field += sin(length(uv + vec2(sin(t), cos(t))) * 7.0);
  float v = 0.5 + 0.125 * field;
  vec3 color = 0.5 + 0.5 * cos(6.28318 * (vec3(0.00, 0.33, 0.67) + v));
  fragColor = vec4(color, 1.0);
}
