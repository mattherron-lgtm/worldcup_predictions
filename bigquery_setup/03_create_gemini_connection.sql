-- =============================================================
-- 03: Create BigQuery connection and Gemini model for AI narratives
-- Run once in the GCP project that hosts the data
-- Requires: BigQuery Connection Admin + BigQuery User IAM roles
-- =============================================================

-- Step 1: Create a BigQuery Remote Connection to Vertex AI
-- Run this via bq CLI or Cloud Console → BigQuery → External Connections
--
-- bq mk --connection \
--   --connection_type=CLOUD_RESOURCE \
--   --location=US \
--   worldcup-gemini-connection
--
-- Then grant the service account Vertex AI User role:
-- gcloud projects add-iam-policy-binding analytics-project-production \
--   --member="serviceAccount:$(bq show --format=json --connection US.worldcup-gemini-connection | jq -r '.cloudResource.serviceAccountId')" \
--   --role="roles/aiplatform.user"

-- Step 2: Create the Gemini model in BQML
CREATE OR REPLACE MODEL `analytics-project-production.worldcup_ml.gemini_flash`
REMOTE WITH CONNECTION `analytics-project-production.US.worldcup-gemini-connection`
OPTIONS (
    endpoint = 'gemini-1.5-flash'
);

-- Step 3: Test the connection
SELECT ml_generate_text_result
FROM ML.GENERATE_TEXT(
    MODEL `analytics-project-production.worldcup_ml.gemini_flash`,
    (SELECT 'Who will win the 2026 FIFA World Cup and why?' AS prompt),
    STRUCT(
        0.7       AS temperature,
        512       AS max_output_tokens,
        TRUE      AS flatten_json_output
    )
);
