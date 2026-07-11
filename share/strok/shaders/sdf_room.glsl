float boxSdf(vec3 p, vec3 b) {
  vec3 q = abs(p) - b;
  return length(max(q, vec3(0.0))) + min(max(q.x, max(q.y, q.z)), 0.0);
}

float sceneSdf(vec3 p) {
  float room = -boxSdf(p, vec3(2.8, 1.7, 3.2));
  vec3 c = p - vec3(0.0, -0.85, 0.0);
  float pillar = boxSdf(c, vec3(0.38, 0.85, 0.38));
  float orb = length(p - vec3(sin(iTime) * 0.8, 0.15, cos(iTime * 0.7) * 0.8)) - 0.45;
  return min(min(room, pillar), orb);
}

vec3 normalAt(vec3 p) {
  vec2 e = vec2(0.001, 0.0);
  return normalize(vec3(
    sceneSdf(p + e.xyy) - sceneSdf(p - e.xyy),
    sceneSdf(p + e.yxy) - sceneSdf(p - e.yxy),
    sceneSdf(p + e.yyx) - sceneSdf(p - e.yyx)));
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
  vec2 uv = (fragCoord * 2.0 - iResolution.xy) / max(iResolution.y, 1.0);
  vec3 ro = vec3(0.0, 0.0, -4.4);
  vec3 rd = normalize(vec3(uv, 1.35));
  float depth = 0.0;
  float hit = 0.0;
  for (int i = 0; i < 80; ++i) {
    vec3 p = ro + rd * depth;
    float d = sceneSdf(p);
    if (abs(d) < 0.002) {
      hit = 1.0;
      break;
    }
    depth += d * 0.65;
    if (depth > 9.0) {
      break;
    }
  }
  vec3 color = vec3(0.03, 0.04, 0.06);
  if (hit > 0.5) {
    vec3 p = ro + rd * depth;
    vec3 n = normalAt(p);
    vec3 light = normalize(vec3(0.4, 0.8, -0.6));
    float shade = 0.18 + 0.82 * max(dot(n, light), 0.0);
    color = vec3(0.45, 0.64, 0.78) * shade;
    color *= exp(-0.08 * depth * depth);
  }
  fragColor = vec4(color, 1.0);
}
