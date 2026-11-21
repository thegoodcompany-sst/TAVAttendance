// Feed one dotenv transaction over stdin. Never echo keys or replace a different keypair.
import { generateKeyPairSync } from "node:crypto";
import { spawnSync } from "node:child_process";

const [target, site] = process.argv.slice(2);
if (
  !target ||
  !site ||
  !/^https:\/\/[a-z0-9-]+\.convex\.site$/.test(site) ||
  (target !== "release" &&
    (target !== "adept-duck-658" ||
      site !== "https://adept-duck-658.convex.site"))
) {
  throw new Error(
    "Supply adept-duck-658 and its HTTPS site, or release and the production site.",
  );
}
if (
  target === "release" &&
  !process.env.CONVEX_DEPLOY_KEY?.startsWith(
    "prod:" + new URL(site).hostname.split(".")[0] + "|",
  )
)
  throw new Error("Production deploy key required.");
if (target !== "release" && process.env.CONVEX_DEPLOY_KEY)
  throw new Error("Unset deploy key for development.");
const { privateKey, publicKey } = generateKeyPairSync("rsa", {
  modulusLength: 2048,
});
const pem = privateKey
  .export({ type: "pkcs8", format: "pem" })
  .trim()
  .replaceAll("\n", " ");
const jwks = JSON.stringify({
  keys: [{ use: "sig", ...publicKey.export({ format: "jwk" }) }],
});
const args = [
  "convex",
  "env",
  "set",
  ...(target === "release" ? [] : ["--deployment", target]),
];
const result = spawnSync("npx", args, {
  input: `JWT_PRIVATE_KEY='${pem}'\nJWKS='${jwks}'\nSITE_URL=${site}\nAPNS_DRY_RUN=true\n`,
  stdio: ["pipe", "ignore", "ignore"],
});
if (result.status !== 0)
  throw new Error(
    "Environment setup failed. Check target, authentication, and existing key names before retrying.",
  );
console.log("Auth configuration installed.");
