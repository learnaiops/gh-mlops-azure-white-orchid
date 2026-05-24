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

  function handleReset() {
    setResult(null);
    setError(null);
  }

  return (
    <div className="app">
      <Header />
      <main className="main-content">
        <div className="container">
          {!result ? (
            <>
              <div className="page-intro">
                <h2>Health Insurance Risk Assessment</h2>
                <p>
                  Enter the customer's details below to predict their insurance
                  risk profile. This tool uses a machine learning model trained
                  on health and lifestyle factors.
                </p>
              </div>
              <RiskForm onSubmit={handleSubmit} loading={loading} />
              {error && (
                <div className="error-banner" role="alert">
                  <span className="error-icon">⚠</span>
                  <span>{error}</span>
                </div>
              )}
            </>
          ) : (
            <RiskResult result={result} onReset={handleReset} />
          )}
        </div>
      </main>
      <footer className="footer">
        <div className="container">
          <p>© 2024 White Orchid — Powered by Azure ML · For demonstration purposes only</p>
        </div>
      </footer>
    </div>
  );
}
