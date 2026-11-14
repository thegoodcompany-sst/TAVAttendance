import "server-only";
import { rpc } from "../rpc";
import type { Missing } from "../types";
export const missingSubmissions = (id: string, from: string, until: string) =>
  rpc<Missing>(id, "admin_missing_submissions", {
    p_from: from,
    p_until: until,
  });
