import { resetDatabase } from "./database";
try {
  await resetDatabase();
  process.stdout.write("Local tp_c demo ready.\n");
} catch (error) {
  if (error instanceof Error && error.message === "TP_SCHEMA_PENDING")
    process.stderr.write("TP_SCHEMA_PENDING\n");
  else process.stderr.write("TP_LOCAL_SETUP_FAILED\n");
  process.exitCode = 1;
}
