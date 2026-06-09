-- =============================================================
-- 01: Create BigQuery datasets for the World Cup predictions project
-- Run once as a setup step before dbt run
-- =============================================================

-- Core prediction datasets (US region to match public data + BQML availability)
CREATE SCHEMA IF NOT EXISTS `analytics-project-production.worldcup_dev`
OPTIONS (location = 'US', description = 'WC 2026 predictions — dev environment');

CREATE SCHEMA IF NOT EXISTS `analytics-project-production.worldcup_predictions`
OPTIONS (location = 'US', description = 'WC 2026 predictions — production');

-- dbt intermediate schemas
CREATE SCHEMA IF NOT EXISTS `analytics-project-production.worldcup_dev_wc_staging`
OPTIONS (location = 'US');

CREATE SCHEMA IF NOT EXISTS `analytics-project-production.worldcup_dev_wc_intermediate`
OPTIONS (location = 'US');

CREATE SCHEMA IF NOT EXISTS `analytics-project-production.worldcup_dev_wc_ml`
OPTIONS (location = 'US');

CREATE SCHEMA IF NOT EXISTS `analytics-project-production.worldcup_dev_wc_predictions`
OPTIONS (location = 'US');

CREATE SCHEMA IF NOT EXISTS `analytics-project-production.worldcup_dev_wc_marts`
OPTIONS (location = 'US');

CREATE SCHEMA IF NOT EXISTS `analytics-project-production.worldcup_dev_wc_seeds`
OPTIONS (location = 'US');

-- Dedicated ML dataset for BQML models
CREATE SCHEMA IF NOT EXISTS `analytics-project-production.worldcup_ml`
OPTIONS (location = 'US', description = 'BQML trained models for WC predictions');

-- Raw data landing zone
CREATE SCHEMA IF NOT EXISTS `analytics-project-production.worldcup_raw`
OPTIONS (location = 'US', description = 'Raw source data — historical results');
