import { defineApp } from "convex/server";
import auth from "@convex-dev/auth/convex.config";
import password from "@convex-dev/auth/components/password/convex.config";
import username from "@convex-dev/auth/components/username/convex.config";

const app = defineApp();
app.use(auth);
app.use(password);
app.use(username);
export default app;
