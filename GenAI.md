# GenAI / LLM Opportunities for White Orchid

> Exploration document — approaches and options for introducing generative AI / LLM
> processing into the health insurance risk MLOps project. **No code yet.**
>
> Author context: Naushad (DevOps engineer learning MLOps on Azure).

## 1. What we have today (recap)

White Orchid is a **classic tabular ML** system:

- A `GradientBoostingClassifier` predicts `high_risk_customer` (binary + probability)
  from 10 structured features (age, BMI, smoker, chronic conditions, income,
  exercise, alcohol, prior claims, family history, region).
- Served via Azure ML online endpoints (pre-prod managed + prod AKS).
- Heavy emphasis on **drift monitoring** — App Insights custom events per prediction
  (`risk_prediction`), Azure ML monitor jobs (Wasserstein / Jensen-Shannon), metric alerts.
- A React/Express UI that calls both endpoints and shows a side-by-side comparison.

The model itself is **not** generative and shouldn't be — for a binary risk score on
tabular data, a gradient-boosted tree is the right tool. GenAI's value here is in the
**layers around the model**: explanation, intake, monitoring, data, and tooling.

## 2. Where GenAI genuinely fits (and where it doesn't)

| Layer | GenAI fit | Why |
|---|---|---|
| **The risk prediction itself** | ❌ Avoid | Tree model is more accurate, cheaper, explainable, and auditable for a binary score. An LLM should not replace it. |
| **Explaining a prediction** | ✅ Strong | Turn score + features into plain-English underwriting rationale. |
| **Data intake / extraction** | ✅ Strong | Parse free-text notes / documents into the 10 structured features. |
| **Drift & monitoring narration** | ✅ Strong | Summarize drift reports and telemetry into actionable narratives. |
| **Synthetic data** | ✅ Good | Generate realistic records for training, testing, and drift simulation. |
| **Underwriter Q&A (RAG)** | ✅ Good | Ground answers in policy/underwriting guideline documents. |
| **DevOps / pipeline copilot** | 🟡 Optional | Summarize pipeline failures, draft IaC — useful but off-domain. |

## 3. Option catalog (ranked by value-to-effort for this repo)

### Option A — Natural-language risk explanations (recommended first) ⭐
**What:** After the model returns `{high_risk, risk_probability}`, an LLM generates a
short, plain-English explanation of *why*, grounded in the actual feature values and
their contribution.

**Grounding matters:** Do **not** let the LLM guess the reasons. Compute feature
contributions first (e.g. SHAP values from the sklearn pipeline) and pass them to the
LLM as facts. The LLM only does the language generation, not the reasoning about
importance. This keeps it auditable.

**Maps to this repo:**
- New backend route alongside `/api/predict` (e.g. `/api/explain`) in `server.js`,
  **or** a separate Azure Function to keep the UI server thin.
- New UI card in `RiskResult.jsx` / `ModelComparison.jsx` — e.g. "Why this decision?".
- Especially powerful in `ModelComparison` — when pre-prod and prod **disagree**, the
  LLM can narrate the difference ("prod weighs prior claims more heavily").

**Azure services:** Azure OpenAI (GPT-4o / 4o-mini), key stored in the existing
Key Vault pattern (`@Microsoft.KeyVault(...)`), telemetry through the existing
App Insights setup.

**Value:** High — directly improves the user-facing product. **Effort:** Low–medium.

---

### Option B — Free-text / document intake → structured features ⭐
**What:** Let an underwriter paste customer notes ("58yo, smokes, two prior claims,
family history of diabetes...") or upload a claims PDF, and have an LLM extract the
10 model features as structured JSON, which then feeds the existing endpoint.

**Maps to this repo:**
- New intake step in `RiskForm.jsx` ("Paste notes / upload document").
- Backend extraction route that returns the same JSON shape the endpoints expect.
- For documents/scans: **Azure AI Document Intelligence** for OCR, then LLM for
  field extraction; for plain text, LLM structured-output (JSON schema / tool calling).

**Guardrails:** Validate extracted values against expected ranges before scoring;
always show the parsed fields for human confirmation (never auto-submit).

**Value:** High — removes manual form entry, a real workflow win. **Effort:** Medium.

---

### Option C — Drift & monitoring narration ⭐
**What:** This project is drift-obsessed (App Insights events, Azure ML monitors,
`simulate_drift.py`, alert rules). An LLM can read the drift report / telemetry query
results and produce a narrative + recommended action:
> "Over the last 7 days BMI shifted +0.12 normalized Wasserstein and smoker rate rose
> 8%. Positive-prediction rate is up 14%. Likely a cohort shift toward higher-risk
> applicants. Recommend reviewing the training baseline and considering a retrain."

**Maps to this repo:**
- A scheduled job (Azure Function timer, or a step in a pipeline) that queries App
  Insights / the Azure ML monitor output and posts an LLM summary to Teams/email via
  the existing `action-groups.tf` action group, or attaches it to the drift pipelines
  (`drift-remediation-pipeline.yml`, `drift-simulate-pipeline.yml`).
- Could enrich the Azure dashboard (`dashboard.tf`) with a generated weekly summary.

**Value:** High for the learning goals (ties GenAI to the MLOps monitoring story).
**Effort:** Medium.

---

### Option D — Synthetic data generation
**What:** The dataset is already synthetic (2,500 rows). Use an LLM (or LLM-assisted
scripting) to generate additional realistic records — including deliberately
**shifted distributions** to drive the drift simulation more realistically than the
current `simulate_drift.py` numeric shifts.

**Maps to this repo:** Feeds `machinelearning/white-orchid/data/` and the
drift-simulation pipeline. Useful for testing the AUC ≥ 0.80 gate against edge cohorts.

**Caveat:** For *training* data, prefer statistical generators (SDV, Faker) over LLMs —
LLMs can introduce subtle bias and are costly at volume. Best used for small,
scenario-specific batches (e.g. "generate 50 high-claim elderly smokers").

**Value:** Medium. **Effort:** Low–medium.

---

### Option E — Underwriter Q&A over policy docs (RAG)
**What:** A chat assistant grounded in underwriting guidelines / policy documents that
answers "What's our policy on chronic conditions for applicants over 60?" alongside the
model's score.

**Maps to this repo:** New service + **Azure AI Search** (vector index) over a document
corpus you'd add; Azure OpenAI for generation. This is the largest net-new surface
(needs a doc corpus that doesn't exist in the repo yet).

**Value:** Medium–high but **higher effort** and needs source documents. Good as a
later phase, not first.

---

### Option F — DevOps / pipeline copilot (off-domain, optional)
**What:** LLM summarizes Azure DevOps pipeline failures, drafts Terraform, or explains
drift alerts in the on-call flow. Useful to *you* as a DevOps engineer but not part of
the insurance product.

**Value:** Convenience. **Effort:** Low. Consider via existing tooling rather than
building into the app.

## 4. Recommended phased roadmap

1. **Phase 1 — Explanations (Option A).** Highest visible value, smallest surface,
   reuses Key Vault + App Insights patterns. Ground with SHAP.
2. **Phase 2 — Intake extraction (Option B).** Adds a real workflow capability;
   introduces structured-output + (optionally) Document Intelligence.
3. **Phase 3 — Drift narration (Option C).** Connects GenAI to the project's core
   MLOps monitoring story — strong learning payoff.
4. **Later — RAG (E) / synthetic data (D) / DevOps copilot (F)** as interest dictates.

## 5. Azure building blocks to use

- **Azure OpenAI Service** — chat/completion models (GPT-4o, 4o-mini for cost). Deploy
  in a supported region (note: current project region is `swedencentral` — confirm model
  availability; Azure OpenAI capacity is region-specific).
- **Azure AI Foundry / Prompt Flow** — author, evaluate, and version prompts; run
  batch evals and LLM-as-judge scoring. Fits naturally next to the Azure ML workspace.
- **Azure AI Document Intelligence** — OCR/layout for document intake (Option B).
- **Azure AI Search** — vector store for RAG (Option E).
- **Azure AI Content Safety** — input/output moderation and prompt-injection screening.

## 6. Architecture & integration notes (consistent with current repo)

- **Secrets:** Store the Azure OpenAI key/endpoint in the **existing Key Vault** and
  expose via the same `@Microsoft.KeyVault(...)` App Service reference pattern already
  used for `ML_ENDPOINT_KEY`. Prefer **Managed Identity** to keyless auth where possible.
- **Telemetry:** Log LLM calls (latency, tokens, cost, prompt/version) to the **existing
  App Insights** — mirrors how `score.py` logs predictions. Enables the same drift/cost
  dashboards.
- **Placement:** Keep the UI server (`server.js`) thin — put LLM logic in a dedicated
  Azure Function or a separate route module so it scales and fails independently of
  prediction calls (the `Promise.allSettled` dual-call pattern already tolerates partial
  failure — a failed explanation must never block the score).
- **IaC:** Add an `cognitive`/`azurerm_cognitive_account` (OpenAI) resource to
  `infra/` (pre-prod) and `infra-prod/`, with diagnostics wired to Log Analytics like
  the other resources.
- **CI/CD:** Add prompt + eval steps to the pipelines so prompt changes are tested
  (LLM-as-judge / golden-set checks) before deploy — the GenAI analogue of the existing
  AUC ≥ 0.80 gate.

## 7. Responsible AI / compliance (important — this is insurance)

Insurance risk decisions about real people are **regulated and high-stakes**. Bake this
in from the start:

- **No autonomous decisions from the LLM.** The tree model makes the decision; the LLM
  only explains, extracts, or summarizes. Keep a human in the loop for underwriting.
- **Ground everything.** Explanations must derive from real feature contributions
  (SHAP), not LLM speculation — otherwise you risk plausible-but-wrong rationales.
- **PII handling.** Health + financial data is sensitive. Use Azure OpenAI (data stays in
  your tenant, not used for training), consider PII redaction, and respect data residency
  (`swedencentral`).
- **Fairness & bias.** Watch that generated explanations don't expose or amplify bias on
  protected attributes (age, region). Review prompts for discriminatory framing.
- **Auditability.** Log prompts, model/version, and outputs (App Insights) so any
  explanation shown to an underwriter can be reconstructed later.
- **Content safety & prompt injection.** Document intake (Option B) ingests untrusted
  text — screen with Azure AI Content Safety and treat extracted values as untrusted
  until validated.

## 8. Suggested concrete next step

Prototype **Option A** behind a feature flag: add a `/api/explain` route, compute SHAP
contributions from the existing pipeline, pass them to Azure OpenAI for a 2–3 sentence
rationale, and render it as a collapsible "Why this decision?" card in `RiskResult.jsx`.
It is self-contained, reuses every existing Azure pattern (Key Vault, App Insights), and
demonstrates the full GenAI + MLOps loop without touching the prediction path.

---
*This is a planning document. No application code has been changed.*
