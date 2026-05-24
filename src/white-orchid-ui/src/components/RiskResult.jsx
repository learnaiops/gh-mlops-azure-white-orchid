export default function RiskResult({ result, onReset }) {
  const isHighRisk = result.high_risk;
  const probability = result.risk_probability ?? 0;
  const pct = Math.round(probability * 100);
  const riskClass = isHighRisk ? "high-risk" : "low-risk";

  return (
    <div>
      <div className={`result-banner ${riskClass}`}>
        <span className="result-icon">{isHighRisk ? "⚠️" : "✅"}</span>
        <div>
          <div className="result-title">
            {isHighRisk ? "High Risk Customer" : "Low Risk Customer"}
          </div>
          <div className="result-subtitle">
            {isHighRisk
              ? "This customer meets the criteria for high insurance risk. A detailed underwriting review is recommended."
              : "This customer presents a low insurance risk profile based on the provided health and lifestyle indicators."}
          </div>
        </div>
      </div>

      <div className="card">
        <div className="card-header">
          <span>📊</span>
          <h3>Risk Analysis</h3>
        </div>
        <div className="card-body">
          <div className="prob-section">
            <div className="prob-label">
              <span>Risk Probability</span>
              <span>{pct}%</span>
            </div>
            <div className="prob-bar-track">
              <div
                className={`prob-bar-fill ${riskClass}`}
                style={{ width: `${pct}%` }}
              />
            </div>
          </div>

          <div className="detail-grid">
            <div className="detail-item">
              <div className="detail-label">Decision</div>
              <div className="detail-value" style={{ color: isHighRisk ? "var(--bupa-red)" : "var(--bupa-green)" }}>
                {isHighRisk ? "High Risk" : "Low Risk"}
              </div>
            </div>
            <div className="detail-item">
              <div className="detail-label">Risk Probability</div>
              <div className="detail-value">{(probability * 100).toFixed(1)}%</div>
            </div>
            <div className="detail-item">
              <div className="detail-label">Model</div>
              <div className="detail-value">{result.model_name ?? "—"}</div>
            </div>
            <div className="detail-item">
              <div className="detail-label">Model Version</div>
              <div className="detail-value">v{result.model_version ?? "—"}</div>
            </div>
          </div>

          <div className="result-actions">
            <button className="btn btn-outline" onClick={onReset}>
              ← New Assessment
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}
