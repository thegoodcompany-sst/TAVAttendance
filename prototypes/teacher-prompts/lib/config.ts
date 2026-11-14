type Environment = Record<string, string | undefined>;
export function assignedDatabase(value: string | undefined): string {
  if (!value || !/^tp_[a-z0-9_]+$/.test(value) || value.length > 63)
    throw new Error("TP_DATABASE_NOT_ASSIGNED");
  return value;
}
export function databaseConfig(env: Environment) {
  if (env.TEACHER_PROMPTS_DEMO !== "1") throw new Error("TP_DEMO_REQUIRED");
  const assigned = env.TP_DB ? assignedDatabase(env.TP_DB) : undefined;
  const raw =
    env.TEACHER_PROMPTS_DATABASE_URL ??
    env.DATABASE_URL ??
    (assigned
      ? `postgresql://postgres@localhost:55432/${assigned}`
      : undefined);
  if (!raw || (!assigned && !env.DATABASE_URL))
    throw new Error("TP_DATABASE_NOT_ASSIGNED");
  let u: URL;
  try {
    u = new URL(raw);
  } catch {
    throw new Error("TP_INVALID_DATABASE_CONFIG");
  }
  if (!["postgresql:", "postgres:"].includes(u.protocol) || u.search || u.hash)
    throw new Error("TP_INVALID_DATABASE_CONFIG");
  const database = assignedDatabase(u.pathname.slice(1));
  if (
    (assigned && assigned !== database) ||
    (env.TEACHER_PROMPTS_DB_NAME && env.TEACHER_PROMPTS_DB_NAME !== database) ||
    (env.DATABASE_URL &&
      env.TEACHER_PROMPTS_DATABASE_URL &&
      env.DATABASE_URL !== raw)
  )
    throw new Error("TP_DATABASE_NAME_MISMATCH");
  const local = ["localhost", "127.0.0.1"].includes(u.hostname);
  if (local && (u.port !== "55432" || u.username !== "postgres" || u.password))
    throw new Error("TP_DATABASE_NOT_ASSIGNED");
  if (
    !local &&
    (env.TP_ALLOW_REMOTE_PREVIEW_DB !== "1" ||
      !env.TP_PREVIEW_ACCESS_CODE?.trim())
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
