// App Insights must be initialised BEFORE any other require so the SDK can
// auto-instrument express routes, outbound HTTP calls, and unhandled exceptions.
const AI_CONN_STR = process.env.APPLICATIONINSIGHTS_CONNECTION_STRING;
if (AI_CONN_STR && !AI_CONN_STR.startsWith("@Microsoft.KeyVault")) {
  const appInsights = require("applicationinsights");
  appInsights
    .setup(AI_CONN_STR)
    .setAutoDependencyCorrelation(true)
    .setAutoCollectRequests(true)
    .setAutoCollectExceptions(true)
    .setAutoCollectPerformance(true)
    .start();
  console.log("Application Insights telemetry enabled");
}

const express = require("express");
const axios = require("axios");
const path = require("path");

const app = express();
app.use(express.json());

// Serve React build
app.use(express.static(path.join(__dirname, "dist")));

// These env vars are populated from Key Vault references in App Service app settings.
// At runtime Azure resolves "@Microsoft.KeyVault(...)" to the actual secret value —
// the code never sees KV syntax.
const ML_ENDPOINT_URL = process.env.ML_ENDPOINT_URL || "";
const ML_ENDPOINT_KEY = process.env.ML_ENDPOINT_KEY || "";

// ── API routes ────────────────────────────────────────────────────────────────

app.post("/api/predict", async (req, res) => {
  if (!ML_ENDPOINT_URL) {
    return res.status(503).json({ error: "ML_ENDPOINT_URL is not configured" });
  }
  if (!ML_ENDPOINT_KEY || ML_ENDPOINT_KEY === "NOT_YET_SET") {
    return res.status(503).json({ error: "ML_ENDPOINT_KEY has not been set in Key Vault yet" });
  }

  try {
    const response = await axios.post(ML_ENDPOINT_URL, req.body, {
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${ML_ENDPOINT_KEY}`,
      },
      timeout: 30000,
    });

    // Azure ML wraps the run() return value as a JSON string when the scoring
    // script returns json.dumps(...) instead of a plain dict/list. Parse it
    // so the browser receives a proper JSON array, not a quoted string.
    let payload = response.data;
    if (typeof payload === "string") {
      try { payload = JSON.parse(payload); } catch (_) {}
    }
    res.json(payload);
  } catch (err) {
    const status = err.response?.status || 502;
    const message = err.response?.data || err.message;
    console.error("ML endpoint error:", message);
    res.status(status).json({ error: "Prediction service error", detail: message });
  }
});

app.get("/api/health", (_req, res) => {
  res.json({
    status: "ok",
    endpoint_configured: !!ML_ENDPOINT_URL,
    endpoint_key_set: !!ML_ENDPOINT_KEY && ML_ENDPOINT_KEY !== "NOT_YET_SET",
    app_insights_enabled: !!AI_CONN_STR,
    timestamp: new Date().toISOString(),
  });
});

// SPA fallback — all unknown routes serve the React app
app.get("*", (_req, res) => {
  res.sendFile(path.join(__dirname, "dist", "index.html"));
});

const PORT = process.env.PORT || 3001;
app.listen(PORT, () => {
  console.log(`White Orchid UI running on port ${PORT}`);
  console.log(`ML endpoint  : ${ML_ENDPOINT_URL || "(not set)"}`);
  console.log(`App Insights : ${AI_CONN_STR ? "enabled" : "disabled"}`);
});
