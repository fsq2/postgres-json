# PostgreSQL Data Streaming Pipeline with Multi-Sink Enrichment and Transformation

## 🎯 Project Overview

This project delivers a comprehensive data streaming solution from PostgreSQL database to three different destinations with advanced enrichment and transformation operations. It's designed to process real-time user engagement events with content in a scalable, fault-tolerant manner.

## 🏗️ Technical Architecture

```
PostgreSQL → Debezium → Redpanda → Spark Structured Streaming → Multi-Sink Fan-out
                                                              ├── ClickHouse (Data Analytics)
                                                              ├── Redis (Real-time Data)
                                                              └── External System (Third-party)
```

## 🧩 Technical Components

### 1. **PostgreSQL** - Source Database
- **Purpose**: Store content catalog and engagement events
- **Tables**: `content` and `engagement_events`
- **Features**: JSONB support, data constraints, foreign keys

### 2. **Debezium** - Change Data Capture (CDC)
- **Purpose**: Capture real-time changes in PostgreSQL
- **Features**: 
  - PostgreSQL 16+ support with `pgoutput` plugin
  - Capture INSERT, UPDATE, DELETE operations
  - Initial snapshots creation
  - Error handling and recovery

### 3. **Redpanda** - Streaming Platform
- **Purpose**: Store and manage data streams
- **Features**:
  - Full Kafka compatibility
  - High read/write performance
  - Automatic topic management
  - Built-in Schema Registry

### 4. **Apache Spark** - Data Processing
- **Purpose**: Transform and enrich data in real-time
- **Features**:
  - Structured Streaming for real-time data
  - Exactly-Once processing
  - Checkpointing support
  - Parallel processing

### 5. **ClickHouse** - Columnar Database
- **Purpose**: Data analytics and reporting
- **Features**:
  - MergeTree engine for high performance
  - Complex query support
  - Advanced data compression
  - Partitioning capabilities

### 6. **Redis** - Real-time Cache
- **Purpose**: Support fast and interactive queries
- **Features**:
  - Streams for time-series data
  - Sorted Sets for time-based aggregations
  - Automatic TTL for data
  - High performance (< 5 seconds)

## 📊 Database Design

### Source PostgreSQL Schema
```sql
-- Content catalog
CREATE TABLE content (
    id              UUID PRIMARY KEY,
    slug            TEXT UNIQUE NOT NULL,
    title           TEXT        NOT NULL,
    content_type    TEXT CHECK (content_type IN ('podcast', 'newsletter', 'video')),
    length_seconds  INTEGER, 
    publish_ts      TIMESTAMPTZ NOT NULL
);

-- Raw engagement telemetry
CREATE TABLE engagement_events (
    id           BIGSERIAL PRIMARY KEY,
    content_id   UUID REFERENCES content(id),
    user_id      UUID,
    event_type   TEXT CHECK (event_type IN ('play', 'pause', 'finish', 'click')),
    event_ts     TIMESTAMPTZ NOT NULL,
    duration_ms  INTEGER,      -- nullable for events without duration
    device       TEXT,         -- e.g. "ios", "web-safari"
    raw_payload  JSONB         -- anything extra the client sends
);
```

### ClickHouse Schema
```sql
-- Content dimension table
CREATE TABLE app.content_dim (
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

-- Enriched engagement facts table
CREATE TABLE app.enriched_engagements (
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
```

## 🔄 Data Transformation and Enrichment

### 1. **Data Joins**
- Join `engagement_events` with `content` to get `content_type` and `length_seconds`
- Use LEFT JOIN to ensure no engagement events are lost

### 2. **Derived Fields**
```python
# Convert duration from milliseconds to seconds
.withColumn("engagement_seconds", col("duration_ms") / 1000.0)

# Calculate engagement percentage
.withColumn("engagement_percent", 
    when((col("length_seconds").isNull()) | (col("length_seconds") == 0), lit(None))
    .otherwise(round((col("engagement_seconds") / col("length_seconds")) * 100.0, 2))
)
```

### 3. **Null Value Handling**
- Handle `NULL` values in `length_seconds` and `duration_ms`
- Set `engagement_percent` to `NULL` when required data is unavailable

## 🎯 Time-based Aggregation Strategy

### Redis Streams for Real-time Aggregations
```python
# Aggregate most engaging content in last 10 minutes
def aggregate_recent_engagement():
    # Use Redis Sorted Sets with TTL
    # Aggregate by content_id with sum of engagement_percent
    # Update every 10 minutes
```

### ClickHouse for Historical Aggregations
```sql
-- Example: Daily average engagement percentage
SELECT 
    toDate(event_ts) as date,
    content_type,
    avg(engagement_percent) as avg_engagement
FROM app.enriched_engagements 
WHERE event_ts >= now() - INTERVAL 30 DAY
GROUP BY date, content_type
ORDER BY date DESC;
```

## 🚀 How to Run

### 1. **Environment Setup**
```bash
# Ensure Docker and Docker Compose are installed
docker --version
docker compose version

# Clone the project
git clone <repository-url>
cd postgres-json
```

### 2. **Start the System**
```bash
# Start all services
./setup.sh

# Test the system
./test_pipeline.sh

# Run data processing
./spark_stream.sh
```

### 3. **Insert Test Data**
```bash
# Insert new content
docker compose exec postgres psql -U postgresuser -d pandashop -c "
INSERT INTO content (id, slug, title, content_type, length_seconds, publish_ts) VALUES
('550e8400-e29b-41d4-a716-446655440000', 'test-episode', 'Test Episode', 'podcast', 1200, NOW());
"

# Insert engagement event
docker compose exec postgres psql -U postgresuser -d pandashop -c "
INSERT INTO engagement_events (content_id, user_id, event_type, event_ts, duration_ms, device, raw_payload) VALUES
('550e8400-e29b-41d4-a716-446655440000', '550e8400-e29b-41d4-a716-446655440001', 'play', NOW(), 30000, 'web', '{\"source\": \"test\"}');
"
```

### 4. **Monitor the System**
```bash
# Comprehensive monitoring
./monitor.sh

# Monitor specific service logs
docker compose logs -f [service-name]

# Check data in ClickHouse
docker compose exec clickhouse clickhouse-client -u app --password app -q "SELECT COUNT(*) FROM app.enriched_engagements;"
```

## 📈 Partitioning Strategy

### ClickHouse
- **Time-based partitioning**: By date (`toDate(event_ts)`)
- **Data ordering**: `(event_ts, content_id, event_id)`
- **Table engine**: `MergeTree` for high performance

### Redis
- **Streams**: Separate by content type
- **TTL**: Automatic deletion of old data
- **Aggregation**: Update every 10 minutes

## 🛡️ Error Handling and Recovery

### 1. **Exactly-Once Processing**
- Use Checkpoints in Spark
- Error handling with Retry Logic
- Operation logging in Redpanda

### 2. **Backfill Mechanism**
```python
# Reprocess historical data
def backfill_historical_data(start_date, end_date):
    # Read data from PostgreSQL
    # Process through same pipeline
    # Send to all destinations
```

### 3. **Monitoring & Alerting**
- Service health monitoring
- Alerts on processing failures
- Performance and efficiency metrics

## 📊 Performance Metrics

### Target Performance Criteria
- **Redis response time**: < 5 seconds
- **Data processing**: 1000+ events/second
- **Processing accuracy**: Exactly-Once
- **System availability**: 99.9%

### Monitoring Metrics
- Events processed per second
- Response time per destination
- Error rates
- Resource utilization

## 🔮 Future Improvements

### 1. **Short Term (1-2 weeks)**
- Add Schema Registry
- Improve partitioning strategy
- Add comprehensive tests

### 2. **Medium Term (1-2 months)**
- Add Kafka Connect Sinks
- Support new content types
- Improve aggregation strategy

### 3. **Long Term (3-6 months)**
- Multi-region support
- Add Machine Learning
- Support Real-time Analytics

## 🧪 Testing

### Unit Tests
```bash
# Connection testing
./test_pipeline.sh

# Performance testing
docker compose exec spark-master /opt/bitnami/spark/bin/spark-submit --class org.apache.spark.examples.SQLPerformanceTest /opt/app/performance_test.py
```

### Integration Tests
- Test data flow from PostgreSQL to all destinations
- Test error handling
- Test performance under load

## 📚 References and Resources

- [Apache Spark Documentation](https://spark.apache.org/docs/latest/)
- [ClickHouse Documentation](https://clickhouse.com/docs/)
- [Redis Streams](https://redis.io/docs/data-types/streams/)
- [Debezium Documentation](https://debezium.io/documentation/)

## 🤝 Contributing and Support

To contribute to the project:
1. Fork the project
2. Create a feature branch
3. Submit a Pull Request
4. Review code and tests

For support:
- Open an Issue on GitHub
- Review documentation files
- Contact the development team

---

**Note**: This project is designed for development and testing environments. For production use, please review security and performance settings. 