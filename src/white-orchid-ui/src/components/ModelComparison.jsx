import RiskResult from "./RiskResult";

export default function ModelComparison({ preprod, prod }) {
  const differ = preprod.high_risk !== prod.high_risk;
  const probDiff = Math.abs(
    (prod.risk_probability ?? 0) - (preprod.risk_probability ?? 0)
  );

  return (
    <div className="comparison-section">
      <div className="comparison-header">
        <h2>Model Comparison</h2>
        {differ ? (
          <span className="comparison-badge drift">
            Predictions differ — possible drift signal
          </span>
        ) : (
          <span className="comparison-badge agree">
            Both models agree
          </span>
        )}
        {!differ && probDiff > 0.1 && (
          <span className="comparison-badge warn">
            Probability gap: {(probDiff * 100).toFixed(1)}%
          </span>
        )}
      </div>

      <div className="comparison-grid">
        <div className="comparison-col">
          <div className="comparison-env-label preprod-label">Pre-Prod</div>
          <RiskResult result={preprod} env="pre-prod" />
        </div>
        <div className="comparison-divider" />
        <div className="comparison-col">
          <div className="comparison-env-label prod-label">Prod (AKS)</div>
          <RiskResult result={prod} env="prod" />
        </div>
      </div>
    </div>
  );
}
