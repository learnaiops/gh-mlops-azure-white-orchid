"""
Scoring script for the Azure ML managed online endpoint.

Loads the trained risk classifier at startup and serves predictions.
Each prediction is logged to Application Insights as a custom event so
that feature distributions can be compared against the training baseline
to detect model drift.

Request format (JSON):
    {"age": 45, "bmi": 27.5, "smoker": 1, "chronic_conditions": 2,
     "annual_income": 50000, "exercise_freq_per_week": 2,
     "alcohol_units_per_week": 8, "num_claims_last_year": 1,
     "family_history": 1, "region": "North"}
    or a list of the above.

Response format (JSON):
    [{"high_risk": true, "risk_probability": 0.87,
      "model_name": "white-orchid-risk-model", "model_version": "3"}]
"""

import glob
import json
import logging
import os
import re

import joblib
import pandas as pd

try:
    from opencensus.ext.azure.log_exporter import AzureLogHandler
    _HAS_APP_INSIGHTS = True
except ImportError:
    _HAS_APP_INSIGHTS = False

FEATURE_COLS = [
    "age", "bmi", "smoker", "chronic_conditions", "annual_income",
    "exercise_freq_per_week", "alcohol_units_per_week",
    "num_claims_last_year", "family_history", "region",
]

model = None
feature_cols = FEATURE_COLS
model_name = "white-orchid-risk-model"
model_version = "unknown"
_ai_logger = None


def _setup_app_insights_logger(connection_string: str) -> logging.Logger:
    logger = logging.getLogger("white-orchid.scoring")
    if connection_string and _HAS_APP_INSIGHTS:
        try:
            logger.addHandler(AzureLogHandler(connection_string=connection_string))
            logger.setLevel(logging.INFO)
        except Exception as exc:
            print(f"App Insights handler setup failed (non-fatal): {exc}")
    return logger


def init():
    global model, feature_cols, model_name, model_version, _ai_logger

    model_dir = os.getenv("AZUREML_MODEL_DIR", "models")

    match = re.search(r"azureml-models/([^/]+)/([^/]+)", model_dir)
    if match:
        model_name = match.group(1)
        model_version = match.group(2)

    model_file = os.path.join(model_dir, "model.pkl")
    if not os.path.exists(model_file):
        candidates = glob.glob(os.path.join(model_dir, "**", "model.pkl"), recursive=True)
        if candidates:
            model_file = candidates[0]
            model_dir = os.path.dirname(model_file)

    model = joblib.load(model_file)

    feature_file = os.path.join(model_dir, "feature_cols.json")
    if os.path.exists(feature_file):
        with open(feature_file) as f:
            feature_cols = json.load(f)

    ai_conn = os.getenv("APPLICATIONINSIGHTS_CONNECTION_STRING", "")
    _ai_logger = _setup_app_insights_logger(ai_conn)

    print(f"Model loaded: {model_name} v{model_version}")


def _log_prediction(item: dict, prob: float, high_risk: bool) -> None:
    """Log each prediction to App Insights for drift monitoring."""
    if _ai_logger is None:
        return
    try:
        _ai_logger.info(
            "risk_prediction",
            extra={
                "custom_dimensions": {
                    "model_name": model_name,
                    "model_version": model_version,
                    "region": str(item.get("region", "unknown")),
                    "high_risk": str(high_risk),
                    "age": str(item.get("age", "")),
                    "bmi": str(item.get("bmi", "")),
                    "smoker": str(item.get("smoker", "")),
                    "risk_probability": f"{prob:.4f}",
                }
            },
        )
    except Exception:
        pass  # Telemetry must never break scoring


def run(raw_data: str) -> str:
    data = json.loads(raw_data)
    if isinstance(data, dict):
        data = [data]

    df = pd.DataFrame(data)[feature_cols]
    probs = model.predict_proba(df)[:, 1]
    preds = (probs >= 0.5).astype(bool)

    results = []
    for i, item in enumerate(data):
        prob = float(probs[i])
        high_risk = bool(preds[i])
        _log_prediction(item, prob, high_risk)
        results.append({
            "high_risk": high_risk,
            "risk_probability": round(prob, 4),
            "model_name": model_name,
            "model_version": model_version,
        })

    return json.dumps(results)
