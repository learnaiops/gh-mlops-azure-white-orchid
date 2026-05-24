import { useState } from "react";
import Header from "./components/Header";
import RiskForm from "./components/RiskForm";
import RiskResult from "./components/RiskResult";

export default function App() {
  const [result, setResult] = useState(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState(null);

  async function handleSubmit(formData) {
    setLoading(true);
    setError(null);
    setResult(null);

    try {
      const response = await fetch("/api/predict", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(formData),
      });

      if (!response.ok) {
        const err = await response.json();
        throw new Error(err.error || `HTTP ${response.status}`);
      }

      const data = await response.json();
      setResult(Array.isArray(data) ? data[0] : data);
    } catch (err) {
      setError(err.message);
    } finally {
      setLoading(false);
    }
  }

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
          {result && (
            <div className="result-section">
              <div className="result-section-label">Assessment Result</div>
              <RiskResult result={result} />
            </div>
          )}
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
