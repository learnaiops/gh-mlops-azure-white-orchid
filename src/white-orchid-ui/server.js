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
const ML_ENDPOINT_URL      = process.env.ML_ENDPOINT_URL      || "";
const ML_ENDPOINT_KEY      = process.env.ML_ENDPOINT_KEY      || "";
const PROD_ML_ENDPOINT_URL = process.env.PROD_ML_ENDPOINT_URL || "";
const PROD_ML_ENDPOINT_KEY = process.env.PROD_ML_ENDPOINT_KEY || "";

async function callEndpoint(url, key, body) {
  const response = await axios.post(url, body, {
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${key}`,
    },
    timeout: 30000,
  });
  let payload = response.data;
  if (typeof payload === "string") {
    try { payload = JSON.parse(payload); } catch (_) {}
  }
  return payload;
}

// ── API routes ────────────────────────────────────────────────────────────────

app.post("/api/predict", async (req, res) => {
  if (!ML_ENDPOINT_URL) {
    return res.status(503).json({ error: "ML_ENDPOINT_URL is not configured" });
  }
  if (!ML_ENDPOINT_KEY || ML_ENDPOINT_KEY === "NOT_YET_SET") {
    return res.status(503).json({ error: "ML_ENDPOINT_KEY has not been set in Key Vault yet" });
  }
  try {
    res.json(await callEndpoint(ML_ENDPOINT_URL, ML_ENDPOINT_KEY, req.body));
  } catch (err) {
    const status = err.response?.status || 502;
    const message = err.response?.data || err.message;
    console.error("Pre-prod ML endpoint error:", message);
    res.status(status).json({ error: "Prediction service error", detail: message });
  }
});

app.post("/api/predict-prod", async (req, res) => {
  if (!PROD_ML_ENDPOINT_URL || PROD_ML_ENDPOINT_URL === "NOT_YET_SET") {
    return res.status(503).json({ error: "Prod endpoint not configured yet — deploy prod infra and run model-promote pipeline first" });
  }
  if (!PROD_ML_ENDPOINT_KEY || PROD_ML_ENDPOINT_KEY === "NOT_YET_SET") {
    return res.status(503).json({ error: "PROD_ML_ENDPOINT_KEY has not been set in Key Vault yet" });
  }
  try {
    res.json(await callEndpoint(PROD_ML_ENDPOINT_URL, PROD_ML_ENDPOINT_KEY, req.body));
  } catch (err) {
    const status = err.response?.status || 502;
    const message = err.response?.data || err.message;
    console.error("Prod ML endpoint error:", message);
    res.status(status).json({ error: "Prod prediction service error", detail: message });
  }
});

app.get("/api/health", (_req, res) => {
  res.json({
    status: "ok",
    preprod_endpoint_configured: !!ML_ENDPOINT_URL,
    preprod_endpoint_key_set: !!ML_ENDPOINT_KEY && ML_ENDPOINT_KEY !== "NOT_YET_SET",
    prod_endpoint_configured: !!PROD_ML_ENDPOINT_URL && PROD_ML_ENDPOINT_URL !== "NOT_YET_SET",
    prod_endpoint_key_set: !!PROD_ML_ENDPOINT_KEY && PROD_ML_ENDPOINT_KEY !== "NOT_YET_SET",
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
