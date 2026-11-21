#!/usr/bin/env node
// Provision (or re-invite) a staff member on the configured Convex deployment and
// activate their account server-side with a password taken from the environment.
// Never prints the password, the invitation secret, or any token.
//
// Usage (from backend/, dev deployment configured in .env.local):
//   STAFF_EMAIL=a@b.c STAFF_NAME="A B" STAFF_ROLE=teacher \
//   STAFF_PASSWORD_ENV=TAVA_V2_EDMUND_PASSWORD node scripts/activate-staff.mjs
import { createHash, randomBytes } from "node:crypto";
import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";

const email = process.env.STAFF_EMAIL;
const name = process.env.STAFF_NAME;
const role = process.env.STAFF_ROLE ?? "teacher";
const pwVar = process.env.STAFF_PASSWORD_ENV ?? "STAFF_PASSWORD";
const password = process.env[pwVar];
if (!email || !name) throw new Error("STAFF_EMAIL and STAFF_NAME are required");
if (!password) throw new Error(`env ${pwVar} is not set`);
if (password.length < 10) throw new Error("password must be at least 10 characters");

if (process.argv.includes("--prod") || process.env.CONVEX_DEPLOY_KEY)
  throw new Error("refusing: this script is for the dev deployment only");
const envLocal = readFileSync(".env.local", "utf8");
const url = (envLocal.match(/^CONVEX_URL=(\S+)/m) ?? [])[1];
if (!url) throw new Error("CONVEX_URL missing from .env.local");

const secret = randomBytes(32).toString("base64url");
const invitationHash = createHash("sha256").update(secret, "utf8").digest("hex");

const run = (fn, args) => {
  try {
    execFileSync("npx", ["convex", "run", fn, JSON.stringify(args)], { stdio: ["ignore", "pipe", "pipe"] });
    return "ok";
  } catch (e) {
    return String(e.stderr ?? e.message);
  }
};
let r = run("staff:provision", { email, name, role, invitationHash });
if (r !== "ok") {
  if (!/TP_CONFLICT/.test(r)) throw new Error(`provision failed: ${r.split("\n").find((l) => /TP_|Error/.test(l)) ?? "unknown"}`);
  r = run("staff:renewInvitation", { email, invitationHash });
  if (r !== "ok") throw new Error(`profile exists and cannot be re-invited (already activated?): ${r.split("\n").find((l) => /TP_|Error/.test(l)) ?? "unknown"}`);
  console.log("existing profile: invitation renewed");
} else console.log("profile provisioned");

const call = async (path, args) => {
  const res = await fetch(`${url}/api/mutation`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ path, format: "json", args }),
  });
  return res.json();
};
const act = await call("auth:activate", { email, invitation: secret, password });
if (act.status !== "success" || act.value?.status !== "complete")
  throw new Error(`activation failed: ${act.errorData ?? act.value?.userError?.error ?? act.errorMessage ?? "unknown"}`);
console.log("account activated");
// Close the session the activation created; the phone signs in with its own.
const out = await call("auth:signOut", { refreshToken: act.value.tokens.refreshToken });
console.log(out.status === "success" ? "activation session closed" : "note: activation session sign-out failed (harmless)");
