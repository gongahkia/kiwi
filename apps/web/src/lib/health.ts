export interface HealthSnapshot {
  checked_at: string;
  service: "web";
  status: "ok";
}

export function getHealthSnapshot(): HealthSnapshot {
  return {
    checked_at: new Date().toISOString(),
    service: "web",
    status: "ok"
  };
}
