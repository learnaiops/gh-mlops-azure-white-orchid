# Model Drift Simulation Plan

A hands-on plan to **learn model drift** on the Big Mac price predictor by making
the training data the *source of truth* in Azure Blob Storage, then deliberately
mutating that data to make the model drift — and observing/detecting it.

## Idea (in one line)

> Train the model from a CSV stored in a blob container, deploy it, capture a
> baseline. Then **change the container contents**, retrain, redeploy — and watch
> the predictions (and monitored metrics) drift away from the baseline.