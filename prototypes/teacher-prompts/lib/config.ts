export function databaseConfig(env: Record<string, string | undefined>) {
  const raw =
    env.TEACHER_PROMPTS_DATABASE_URL ??
    env.DATABASE_URL ??
    "postgresql://postgres@localhost:55432/tp_c";
  const u = new URL(raw);
  const local = ["localhost", "127.0.0.1"].includes(u.hostname);
  const assigned = env.TEACHER_PROMPTS_DB_NAME ?? "tp_c";
  if (
    !/^[a-z][a-z0-9_]{0,62}$/.test(assigned) ||
    ["postgres", "template0", "template1"].includes(assigned)
  )
    throw new Error("TP_DATABASE_NOT_ASSIGNED");
  if (!["postgresql:", "postgres:"].includes(u.protocol) || u.search || u.hash)
    throw new Error("TP_INVALID_DATABASE_CONFIG");
  if (!local && env.TP_ALLOW_REMOTE_PREVIEW_DB !== "1")
    throw new Error("TP_REMOTE_DATABASE_REFUSED");
  if (
    local &&
    (u.port !== "55432" ||
      u.username !== "postgres" ||
      u.password ||
      u.pathname !== "/" + assigned)
  )
    throw new Error("TP_DATABASE_NOT_ASSIGNED");
  if (
    env.TEACHER_PROMPTS_DB_NAME &&
    env.TEACHER_PROMPTS_DB_NAME !== u.pathname.slice(1)
  )
    throw new Error("TP_DATABASE_NAME_MISMATCH");
  return {
    connectionString: raw,
    max: 5,
    connectionTimeoutMillis: 5000,
    idleTimeoutMillis: 10000,
  };
}
