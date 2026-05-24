import { useState } from "react";
import Header from "./components/Header";
import RiskForm from "./components/RiskForm";
import RiskResult from "./components/RiskResult";
import ModelComparison from "./components/ModelComparison";

export default function App() {
  const [preprodResult, setPreprodResult] = useState(null);
  const [prodResult, setProdResult] = useState(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState(null);

  async function handleSubmit(formData) {
    setLoading(true);
    setError(null);
    setPreprodResult(null);
    setProdResult(null);

    const [preprod, prod] = await Promise.allSettled([
      fetch("/api/predict", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(formData),
      }).then(async (r) => {
        if (!r.ok) {
          const e = await r.json();
          throw new Error(e.error || `HTTP ${r.status}`);
        }
        const data = await r.json();
        return Array.isArray(data) ? data[0] : data;
      }),
      fetch("/api/predict-prod", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(formData),
      }).then(async (r) => {
        if (!r.ok) {
          const e = await r.json();
          throw new Error(e.error || `HTTP ${r.status}`);
        }
        const data = await r.json();
        return Array.isArray(data) ? data[0] : data;
      }),
    ]);

    setLoading(false);

    if (preprod.status === "fulfilled") {
      setPreprodResult(preprod.value);
    } else {
      setError(`Pre-prod: ${preprod.reason?.message}`);
    }

    if (prod.status === "fulfilled") {
      setProdResult(prod.value);
    }
  }

  const bothLoaded = preprodResult && prodResult;

  return (
    <div className="app">
      <Header />

      <div className="hero">
        <div className="hero-inner">
          <div className="hero-tag">
            <span className="dot" />
            AI-Powered Underwriting
          </div>
          <h1>
            Predict insurance risk<br />
            with <span>machine learning</span>
          </h1>
          <p>
            Enter a customer profile and our gradient boosting model —
            trained on health, lifestyle, and claims data — returns an
            instant risk decision with probability score.
            Results are shown from both pre-prod and prod endpoints simultaneously.
          </p>
        </div>
      </div>

      <main className="main-content">
        <div className="container">
          <RiskForm onSubmit={handleSubmit} loading={loading} />

          {error && (
            <div className="error-banner" role="alert">
              <span>⚠</span>
              <span>{error}</span>
            </div>
          )}

          {bothLoaded ? (
            <ModelComparison preprod={preprodResult} prod={prodResult} />
          ) : preprodResult ? (
            <div className="result-section">
              <div className="result-section-label">Pre-Prod Assessment</div>
              <RiskResult result={preprodResult} env="pre-prod" />
            </div>
          ) : null}
        </div>
      </main>

      <footer className="footer">
        <div className="container">
          <p>© 2025 White Orchid · AI Risk Intelligence · Powered by Azure ML · For demonstration purposes only</p>
        </div>
      </footer>
    </div>
  );
}
