import { Hono } from "hono";
import { bearerAuth } from "hono/bearer-auth";
import { HTTPException } from "hono/http-exception";
import aiRoutes from "./routes/ai";
import entitiesRoutes from "./routes/entities";
import mediaRoutes from "./routes/media";
import relationshipsRoutes from "./routes/relationships";
import searchRoutes from "./routes/search";
import type { Bindings } from "./types";

const app = new Hono<{ Bindings: Bindings }>();

app.use("/api/*", (c, next) => {
  const auth = bearerAuth({ token: c.env.API_TOKEN });
  return auth(c as unknown as Parameters<typeof auth>[0], next);
});

app.route("/api", entitiesRoutes);
app.route("/api", relationshipsRoutes);
app.route("/api", mediaRoutes);
app.route("/api", searchRoutes);
app.route("/api", aiRoutes);

app.notFound((c) => c.json({ error: "Not found" }, 404));

app.onError((err, c) => {
  if (err instanceof HTTPException) {
    const fallback = err.status === 401 ? "Unauthorized" : "Request failed";
    return c.json({ error: err.message || fallback }, err.status);
  }
  console.error(err);
  return c.json({ error: "Internal error" }, 500);
});

export default app;
