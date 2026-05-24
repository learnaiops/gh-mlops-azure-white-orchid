"""
Health insurance risk classification training script.

Reads the dataset from a mounted path (local CSV or AML datastore mount),
trains a GradientBoostingClassifier, logs all metrics to MLflow, and sends
custom telemetry to Application Insights for drift baseline tracking.

AUC quality gate: if test AUC < 0.80 the script exits with an error,
which causes the AML training job to fail and blocks deployment.

Usage:
    python train.py --data data/health_insurance_risk_dataset.csv --out models
"""

import argparse
import glob
import hashlib
import json
import os
import sys

import joblib
import numpy as np
import pandas as pd
from sklearn.compose import ColumnTransformer
from sklearn.ensemble import GradientBoostingClassifier
from sklearn.metrics import classification_report, roc_auc_score
from sklearn.model_selection import cross_val_score, train_test_split
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import OneHotEncoder, StandardScaler

AUC_THRESHOLD = 0.80

FEATURE_COLS = [
    "age", "bmi", "smoker", "chronic_conditions", "annual_income",
    "exercise_freq_per_week", "alcohol_units_per_week",
    "num_claims_last_year", "family_history", "region",
]
TARGET_COL = "high_risk_customer"

try:
    import mlflow
    _HAS_MLFLOW = True
except ImportError:
    _HAS_MLFLOW = False

try:
    import logging
    from opencensus.ext.azure.log_exporter import AzureLogHandler
    _HAS_APP_INSIGHTS = True
except ImportError:
    _HAS_APP_INSIGHTS = False


def resolve_csv(data_path: str) -> str:
    if os.path.isdir(data_path):
        matches = glob.glob(os.path.join(data_path, "**", "*.csv"), recursive=True)
        if not matches:
            raise FileNotFoundError(f"No CSV found under {data_path}")
        return matches[0]
    return data_path


def file_hash(path: str) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(8192), b""):
            h.update(chunk)
    return h.hexdigest()


def send_to_app_insights(connection_string: str, dimensions: dict) -> None:
    """Log training telemetry to App Insights as a custom event for drift tracking."""
    if not _HAS_APP_INSIGHTS or not connection_string:
        print("App Insights logging skipped (package or connection string not available)")
        return
    try:
        logger = logging.getLogger("white-orchid.training")
        if not any(isinstance(h, AzureLogHandler) for h in logger.handlers):
            logger.addHandler(AzureLogHandler(connection_string=connection_string))
        logger.setLevel(logging.INFO)
        logger.info(
            "model_training_completed",
            extra={"custom_dimensions": {k: str(v) for k, v in dimensions.items()}},
        )
        print("Training metrics sent to Application Insights")
    except Exception as exc:
        print(f"App Insights logging failed (non-fatal): {exc}")


def build_pipeline() -> Pipeline:
    numeric_features = [c for c in FEATURE_COLS if c != "region"]
    categorical_features = ["region"]

    preprocessor = ColumnTransformer([
        ("num", StandardScaler(), numeric_features),
        ("cat", OneHotEncoder(handle_unknown="ignore", sparse_output=False), categorical_features),
    ])

    return Pipeline([
        ("preprocessor", preprocessor),
        ("clf", GradientBoostingClassifier(
            n_estimators=200,
            learning_rate=0.1,
            max_depth=4,
            subsample=0.8,
            random_state=42,
        )),
    ])


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--data", required=True, help="CSV file or directory")
    parser.add_argument("--out", default="models", help="Output dir for artifacts")
    args = parser.parse_args()

    csv_path = resolve_csv(args.data)
    print(f"Training from: {csv_path}")

    df = pd.read_csv(csv_path)
    X = df[FEATURE_COLS]
    y = df[TARGET_COL]

    # Data fingerprint for drift baseline — compare across runs to detect drift
    data_stats = {
        "rows": int(len(df)),
        "positive_rate": float(y.mean()),
        "age_mean": float(df["age"].mean()),
        "age_std": float(df["age"].std()),
        "bmi_mean": float(df["bmi"].mean()),
        "smoker_rate": float(df["smoker"].mean()),
        "chronic_conditions_mean": float(df["chronic_conditions"].mean()),
        "num_claims_mean": float(df["num_claims_last_year"].mean()),
        "input_sha256": file_hash(csv_path),
    }
    print("Data stats:", json.dumps(data_stats, indent=2))

    X_train, X_test, y_train, y_test = train_test_split(
        X, y, test_size=0.2, random_state=42, stratify=y
    )

    model = build_pipeline()

    # 5-fold CV AUC on full dataset before final fit
    cv_auc = cross_val_score(model, X, y, cv=5, scoring="roc_auc", n_jobs=-1)

    model.fit(X_train, y_train)
    y_prob = model.predict_proba(X_test)[:, 1]
    y_pred = model.predict(X_test)

    test_auc = float(roc_auc_score(y_test, y_prob))

    metrics = {
        "test_auc": test_auc,
        "cv_auc_mean": float(cv_auc.mean()),
        "cv_auc_std": float(cv_auc.std()),
    }
    print("Metrics:", json.dumps(metrics, indent=2))
    print(classification_report(y_test, y_pred))

    # AUC quality gate — fail the job if below threshold
    if test_auc < AUC_THRESHOLD:
        print(f"##[error]AUC {test_auc:.4f} is below the required threshold of {AUC_THRESHOLD}. Deployment blocked.")
        sys.exit(1)

    print(f"AUC {test_auc:.4f} >= {AUC_THRESHOLD} — quality gate passed.")

    # MLflow — cross-run drift comparison baseline
    if _HAS_MLFLOW:
        mlflow.log_params({
            "n_estimators": 200,
            "learning_rate": 0.1,
            "max_depth": 4,
            "subsample": 0.8,
            "input_sha256": data_stats["input_sha256"],
        })
        mlflow.log_metrics({
            **metrics,
            **{k: v for k, v in data_stats.items() if k != "input_sha256"},
        })

    # App Insights — telemetry for monitoring and drift detection
    ai_conn = os.getenv("APPLICATIONINSIGHTS_CONNECTION_STRING", "")
    send_to_app_insights(ai_conn, {**metrics, **data_stats})

    # Save deployable artifacts
    os.makedirs(args.out, exist_ok=True)
    joblib.dump(model, os.path.join(args.out, "model.pkl"))
    with open(os.path.join(args.out, "feature_cols.json"), "w") as f:
        json.dump(FEATURE_COLS, f, indent=2)
    with open(os.path.join(args.out, "data_stats.json"), "w") as f:
        json.dump({**data_stats, **metrics}, f, indent=2)

    print(f"Artifacts written to {args.out}")


if __name__ == "__main__":
    main()
