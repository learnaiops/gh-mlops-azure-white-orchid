import { useState } from "react";

const DEFAULTS = {
  age: 35,
  bmi: 25.0,
  smoker: 0,
  chronic_conditions: 0,
  annual_income: 60000,
  exercise_freq_per_week: 3,
  alcohol_units_per_week: 4,
  num_claims_last_year: 0,
  family_history: 0,
  region: "North",
};

const REGIONS = ["North", "South", "East", "West"];

export default function RiskForm({ onSubmit, loading }) {
  const [form, setForm] = useState(DEFAULTS);

  function handleChange(e) {
    const { name, value, type } = e.target;
    setForm((prev) => ({
      ...prev,
      [name]: type === "number" ? parseFloat(value) : value,
    }));
  }

  function handleSubmit(e) {
    e.preventDefault();
    onSubmit(form);
  }

  return (
    <div className="card">
      <div className="card-header">
        <span>👤</span>
        <h3>Customer Details</h3>
      </div>
      <div className="card-body">
        <form onSubmit={handleSubmit}>
          <div className="form-grid">
            <div className="form-group">
              <label htmlFor="age">Age <span className="hint">(years)</span></label>
              <input
                id="age"
                type="number"
                name="age"
                min="18"
                max="100"
                value={form.age}
                onChange={handleChange}
                required
              />
            </div>

            <div className="form-group">
              <label htmlFor="bmi">BMI</label>
              <input
                id="bmi"
                type="number"
                name="bmi"
                min="10"
                max="60"
                step="0.1"
                value={form.bmi}
                onChange={handleChange}
                required
              />
            </div>

            <div className="form-group">
              <label htmlFor="smoker">Smoker</label>
              <div className="select-wrapper">
                <select id="smoker" name="smoker" value={form.smoker} onChange={handleChange}>
                  <option value={0}>No</option>
                  <option value={1}>Yes</option>
                </select>
              </div>
            </div>

            <div className="form-group">
              <label htmlFor="chronic_conditions">Chronic Conditions <span className="hint">(count)</span></label>
              <input
                id="chronic_conditions"
                type="number"
                name="chronic_conditions"
                min="0"
                max="10"
                value={form.chronic_conditions}
                onChange={handleChange}
                required
              />
            </div>

            <div className="form-group">
              <label htmlFor="annual_income">Annual Income <span className="hint">(£)</span></label>
              <input
                id="annual_income"
                type="number"
                name="annual_income"
                min="0"
                step="1000"
                value={form.annual_income}
                onChange={handleChange}
                required
              />
            </div>

            <div className="form-group">
              <label htmlFor="exercise_freq_per_week">Exercise <span className="hint">(times/week)</span></label>
              <input
                id="exercise_freq_per_week"
                type="number"
                name="exercise_freq_per_week"
                min="0"
                max="14"
                value={form.exercise_freq_per_week}
                onChange={handleChange}
                required
              />
            </div>

            <div className="form-group">
              <label htmlFor="alcohol_units_per_week">Alcohol <span className="hint">(units/week)</span></label>
              <input
                id="alcohol_units_per_week"
                type="number"
                name="alcohol_units_per_week"
                min="0"
                max="100"
                value={form.alcohol_units_per_week}
                onChange={handleChange}
                required
              />
            </div>

            <div className="form-group">
              <label htmlFor="num_claims_last_year">Claims Last Year</label>
              <input
                id="num_claims_last_year"
                type="number"
                name="num_claims_last_year"
                min="0"
                max="20"
                value={form.num_claims_last_year}
                onChange={handleChange}
                required
              />
            </div>

            <div className="form-group">
              <label htmlFor="family_history">Family Medical History</label>
              <div className="select-wrapper">
                <select id="family_history" name="family_history" value={form.family_history} onChange={handleChange}>
                  <option value={0}>No significant history</option>
                  <option value={1}>Known conditions</option>
                </select>
              </div>
            </div>

            <div className="form-group">
              <label htmlFor="region">Region</label>
              <div className="select-wrapper">
                <select id="region" name="region" value={form.region} onChange={handleChange}>
                  {REGIONS.map((r) => (
                    <option key={r} value={r}>{r}</option>
                  ))}
                </select>
              </div>
            </div>
          </div>

          <div className="form-actions">
            <button type="submit" className="btn btn-primary" disabled={loading}>
              {loading ? (
                <>
                  <span className="spinner" />
                  Assessing…
                </>
              ) : (
                <>Assess Risk</>
              )}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}
