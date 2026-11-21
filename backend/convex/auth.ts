import { setupConvexAuth } from "@convex-dev/auth/server";
import { setupUsernamePassword } from "@convex-dev/auth/methods/username-password/server";
import type { RegisteredMutation } from "convex/server";
import { v } from "convex/values";
import { components, internal } from "./_generated/api";
import { mutation, type MutationCtx, type QueryCtx } from "./_generated/server";
import { digest, emailKey, fail } from "./lib/common";

const core = setupConvexAuth({ component: components.auth });
export const { signOut, refreshSession, isAuthenticated } = core;

// Staff email is the login. Its immutable staff UUID is the component's username.
// Keep the raw recipe unexported: only the invitation-checked mutation can sign up.
const passwordMethod = setupUsernamePassword(core, {
  component: components.authPassword,
  usernameComponent: components.authUsername,
}).attachUserCallbacks({ createUser: internal.staff.createPasswordUser });

// Convex does not expose a public builder for wrapping a registered mutation.
// Keep the registration detail here and infer both wire types from the recipe.
function recipeHandler<A extends Record<string, unknown>, R>(
  fn: RegisteredMutation<"public", A, R>,
) {
  return (fn as typeof fn & { _handler: (ctx: MutationCtx, args: A) => R })
    ._handler;
}
const signUp = recipeHandler(passwordMethod.signUpWithUsernamePassword);
const verifyPassword = recipeHandler(passwordMethod.signInWithUsernamePassword);

function staffByEmail(ctx: QueryCtx, email: string) {
  const normalized = emailKey(email);
  return ctx.db
    .query("profiles")
    .withIndex("email", (q) => q.eq("email", normalized))
    .unique();
}

const text = v.string();
const credentials = { email: text, password: text };

export const activate = mutation({
  args: { ...credentials, invitation: text },
  handler: async (ctx, { email, password, invitation }) => {
    const staff = await staffByEmail(ctx, email);
    if (
      !staff?.active ||
      staff.user ||
      !staff.invitationHash ||
      (staff.invitationExpires ?? 0) <= Date.now() ||
      (await digest(invitation)) !== staff.invitationHash
    )
      fail("TP_NOT_AVAILABLE");
    // Invoke the package handler inside this transaction, so the invitation,
    // user, credential and first session commit or roll back together.
    const result = await signUp(ctx, {
      username: staff.uuid,
      password,
    });
    if (result.status === "complete") {
      const user = ctx.db.normalizeId("users", result.tokens.userId);
      if (!user) throw new Error("Invalid auth user ID");
      await ctx.db.patch(staff._id, {
        user,
        invitationHash: undefined,
        invitationExpires: undefined,
      });
    }
    return result;
  },
});

export const signIn = mutation({
  args: credentials,
  handler: async (ctx, { email, password }) => {
    const staff = await staffByEmail(ctx, email);
    if (staff?.active && staff.user) {
      const result = await verifyPassword(ctx, {
        username: staff.uuid,
        password,
      });
      if (result.status === "complete") {
        if (result.tokens.userId !== staff.user)
          throw new Error("Staff credential link mismatch");
        return result;
      }
    }
    // Return a rejection (throwing would roll back the password rate limiter).
    return {
      status: "error" as const,
      userError: { error: "INVALID_CREDENTIALS" as const },
    };
  },
});
