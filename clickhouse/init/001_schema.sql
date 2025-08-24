CREATE DATABASE IF NOT EXISTS app;

CREATE TABLE IF NOT EXISTS app.content_dim (
  id              UUID,
  slug            String,
  title           String,
  content_type    LowCardinality(String),
  length_seconds  Int32,
  publish_ts      DateTime64(3),
  version_ts_ms   UInt64
)
ENGINE = ReplacingMergeTree(version_ts_ms)
ORDER BY id;

CREATE TABLE IF NOT EXISTS app.enriched_engagements (
  event_id        UInt64,
  content_id      UUID,
  user_id         UUID,
  event_type      LowCardinality(String),
  event_ts        DateTime64(3),
  duration_ms     Int32,
  device          String,
  engagement_seconds Float64,
  engagement_percent Float64,
  content_slug    String,
  content_title   String,
  content_type    LowCardinality(String),
  length_seconds  Int32,
  publish_ts      DateTime64(3),
  loaded_at       DateTime DEFAULT now()
)
ENGINE = MergeTree
ORDER BY (event_ts, content_id, event_id);

-- Alternative table name that matches the original Spark code
CREATE TABLE IF NOT EXISTS app.engagement_facts (
  event_id        UInt64,
  content_id      UUID,
  user_id         UUID,
  event_type      LowCardinality(String),
  event_ts        DateTime64(3),
  duration_ms     Int32,
  device          String,
  engagement_seconds Float64,
  engagement_percent Float64,
  content_slug    String,
  content_title   String,
  content_type    LowCardinality(String),
  length_seconds  Int32,
  publish_ts      DateTime64(3),
  loaded_at       DateTime DEFAULT now()
)
ENGINE = MergeTree
ORDER BY (event_ts, content_id, event_id);
