/* eslint-disable */
/**
 * Generated `api` utility.
 *
 * THIS CODE IS AUTOMATICALLY GENERATED.
 *
 * To regenerate, run `npx convex dev`.
 * @module
 */

import type * as auth from "../auth.js";
import type * as calendar from "../calendar.js";
import type * as crons from "../crons.js";
import type * as devices from "../devices.js";
import type * as http from "../http.js";
import type * as lib_common from "../lib/common.js";
import type * as lib_planner from "../lib/planner.js";
import type * as lib_projection from "../lib/projection.js";
import type * as lib_push_apns_http2 from "../lib/push/apns_http2.js";
import type * as lib_push_apns_sender from "../lib/push/apns_sender.js";
import type * as lib_push_dry_run_sender from "../lib/push/dry_run_sender.js";
import type * as lib_push_prompt_dispatch from "../lib/push/prompt_dispatch.js";
import type * as lib_push_prompt_payload from "../lib/push/prompt_payload.js";
import type * as lib_push_prompt_strings from "../lib/push/prompt_strings.js";
import type * as push from "../push.js";
import type * as queue from "../queue.js";
import type * as seed from "../seed.js";
import type * as settings from "../settings.js";
import type * as staff from "../staff.js";
import type * as teacher from "../teacher.js";

import type {
  ApiFromModules,
  FilterApi,
  FunctionReference,
} from "convex/server";

declare const fullApi: ApiFromModules<{
  auth: typeof auth;
  calendar: typeof calendar;
  crons: typeof crons;
  devices: typeof devices;
  http: typeof http;
  "lib/common": typeof lib_common;
  "lib/planner": typeof lib_planner;
  "lib/projection": typeof lib_projection;
  "lib/push/apns_http2": typeof lib_push_apns_http2;
  "lib/push/apns_sender": typeof lib_push_apns_sender;
  "lib/push/dry_run_sender": typeof lib_push_dry_run_sender;
  "lib/push/prompt_dispatch": typeof lib_push_prompt_dispatch;
  "lib/push/prompt_payload": typeof lib_push_prompt_payload;
  "lib/push/prompt_strings": typeof lib_push_prompt_strings;
  push: typeof push;
  queue: typeof queue;
  seed: typeof seed;
  settings: typeof settings;
  staff: typeof staff;
  teacher: typeof teacher;
}>;

/**
 * A utility for referencing Convex functions in your app's public API.
 *
 * Usage:
 * ```js
 * const myFunctionReference = api.myModule.myFunction;
 * ```
 */
export declare const api: FilterApi<
  typeof fullApi,
  FunctionReference<any, "public">
>;

/**
 * A utility for referencing Convex functions in your app's internal API.
 *
 * Usage:
 * ```js
 * const myFunctionReference = internal.myModule.myFunction;
 * ```
 */
export declare const internal: FilterApi<
  typeof fullApi,
  FunctionReference<any, "internal">
>;

export declare const components: {
  auth: import("@convex-dev/auth/_generated/component.js").ComponentApi<"auth">;
  authPassword: import("@convex-dev/auth/components/password/_generated/component.js").ComponentApi<"authPassword">;
  authUsername: import("@convex-dev/auth/components/username/_generated/component.js").ComponentApi<"authUsername">;
};
