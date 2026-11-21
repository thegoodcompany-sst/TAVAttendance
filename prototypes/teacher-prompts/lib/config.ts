type Environment = Record<string, string | undefined>;
export function assignedDatabase(value: string | undefined): string {
  if (!value || !/^tp_[a-z0-9_]+$/.test(value) || value.length > 63)
    throw new Error("TP_DATABASE_NOT_ASSIGNED");
  return value;
}
export function databaseConfig(env: Environment) {
  if (env.TEACHER_PROMPTS_DEMO !== "1") throw new Error("TP_DEMO_REQUIRED");
  const assigned = assignedDatabase(env.TP_DB);
  const raw =
    env.TP_DATABASE_URL ?? `postgresql://postgres@localhost:55432/${assigned}`;
  let u: URL;
  try {
    u = new URL(raw);
  } catch {
    throw new Error("TP_INVALID_DATABASE_CONFIG");
  }
  if (!["postgresql:", "postgres:"].includes(u.protocol) || u.hash)
    throw new Error("TP_INVALID_DATABASE_CONFIG");
  const database = assignedDatabase(u.pathname.slice(1));
  if (assigned !== database) throw new Error("TP_DATABASE_NAME_MISMATCH");
  const local = ["localhost", "127.0.0.1"].includes(u.hostname);
  if (
    local &&
    (u.port !== "55432" || u.username !== "postgres" || u.password || u.search)
  )
    throw new Error("TP_DATABASE_NOT_ASSIGNED");
  if (
    env.TP_PREVIEW_ACCESS_CODE !== undefined &&
    env.TP_PREVIEW_ACCESS_CODE.trim().length < 24
  )
    throw new Error("TP_PREVIEW_CODE_REQUIRED");
  if (
    !local &&
    (env.TP_ALLOW_REMOTE_PREVIEW_DB !== "1" ||
      !env.TP_PREVIEW_ACCESS_CODE ||
      env.TP_PREVIEW_ACCESS_CODE.trim().length < 24 ||
      u.search !== "?sslmode=require" ||
      !u.hostname)
  )
    throw new Error("TP_REMOTE_DATABASE_REFUSED");
  // Explicit driver fields prevent inherited PG* credentials/options from being used.
  return {
    host: u.hostname,
    port: Number(u.port || 5432),
    database,
    user: decodeURIComponent(u.username) || "postgres",
    password: () => decodeURIComponent(u.password),
    options: "-c timezone=Asia/Singapore",
    client_encoding: "UTF8",
    replication: "false",
    sslnegotiation: "postgres" as const,
    application_name: "teacher-prompts-demo",
    ssl: local ? false : { rejectUnauthorized: true },
    max: 5,
    connectionTimeoutMillis: 5000,
    idleTimeoutMillis: 10000,
  };
}
export function previewAccessRequired(env: Environment) {
  const config = databaseConfig(env);
  return (
    !["localhost", "127.0.0.1"].includes(config.host) ||
    Boolean(env.TP_PREVIEW_ACCESS_CODE?.trim())
  );
}
