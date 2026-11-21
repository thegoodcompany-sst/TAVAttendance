import { Password } from "@convex-dev/auth/providers/Password";
import { convexAuth } from "@convex-dev/auth/server";
import { digest, emailKey, fail } from "./lib/common";
import type { MutationCtx } from "./_generated/server";

export const { auth, signIn, signOut, store, isAuthenticated } = convexAuth({
  providers: [
    Password({
      profile(params) {
        if (typeof params.email !== "string") fail("TP_INVALID_INPUT");
        return {
          email: emailKey(params.email),
          invitation:
            params.flow === "signUp" && typeof params.invitation === "string"
              ? params.invitation
              : "",
        };
      },
    }),
  ],
  callbacks: {
    async createOrUpdateUser(context, { type, provider, profile }) {
      const ctx = context as MutationCtx;
      if (
        type !== "credentials" ||
        provider.id !== "password" ||
        !profile.email ||
        typeof profile.invitation !== "string"
      )
        fail("TP_NOT_AVAILABLE");
      const staff = await ctx.db
        .query("profiles")
        .withIndex("email", (q) => q.eq("email", profile.email!))
        .unique();
      if (
        !staff?.active ||
        staff.user ||
        !staff.invitationHash ||
        (staff.invitationExpires ?? 0) <= Date.now() ||
        (await digest(profile.invitation)) !== staff.invitationHash
      )
        fail("TP_NOT_AVAILABLE");
      const user = await ctx.db.insert("users", { email: staff.email });
      await ctx.db.patch(staff._id, {
        user,
        invitationHash: undefined,
        invitationExpires: undefined,
      });
      return user;
    },
    async beforeSessionCreation(context, { userId }) {
      const ctx = context as MutationCtx;
      if (
        !(
          await ctx.db
            .query("profiles")
            .withIndex("user", (q) => q.eq("user", userId))
            .unique()
        )?.active
      )
        fail("TP_NOT_AVAILABLE");
    },
  },
});
