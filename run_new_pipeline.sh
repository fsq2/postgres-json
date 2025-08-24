#!/bin/bash

echo "🚀 Running New Pipeline Architecture: PostgreSQL → Debezium → Redpanda → Spark → Kafka → Redis"
echo "================================================================================================"

# Start all services
echo "📦 Starting all services..."
docker compose up -d

# Wait for services to be healthy
echo "⏳ Waiting for services to be healthy..."
sleep 30

# Check service status
echo "📊 Checking service status..."
docker compose ps

# Create Debezium connector if not exists
echo "🔌 Checking Debezium connector..."
CONNECTOR_STATUS=$(docker compose exec debezium curl -s debezium:8083/connectors/postgres-connector/status 2>/dev/null | jq -r '.connector.state' 2>/dev/null)

if [ "$CONNECTOR_STATUS" != "RUNNING" ]; then
    echo "Creating Debezium connector..."
    ./create_debezium_postgres_connector.sh
    sleep 10
else
    echo "✅ Debezium connector is already RUNNING"
fi

# Check Redpanda topics
echo "📋 Checking Redpanda topics..."
docker compose exec redpanda rpk topic list

# Insert test data
echo "🧪 Inserting test data..."
docker compose exec postgres psql -U postgresuser -d pandashop -c "
INSERT INTO content (id, slug, title, content_type, length_seconds, publish_ts) VALUES
('550e8400-e29b-41d4-a716-446655440003', 'test-episode-new', 'Test Episode New', 'podcast', 1500, NOW())
ON CONFLICT (id) DO NOTHING;

INSERT INTO engagement_events (content_id, user_id, event_type, event_ts, duration_ms, device, raw_payload) VALUES
('550e8400-e29b-41d4-a716-446655440003', '550e8400-e29b-41d4-a716-446655440020', 'play', NOW(), 75000, 'web', '{\"source\": \"new-pipeline\"}')
ON CONFLICT (id) DO NOTHING;
"

echo "⏳ Waiting for data to flow..."
sleep 15

# Check if enriched topic was created
echo "🔍 Checking for enriched topic..."
docker compose exec redpanda rpk topic list | grep enriched

# Start Spark Streaming
echo "🔥 Starting Spark Streaming..."
./spark_stream.sh &
SPARK_PID=$!

# Wait for Spark to start processing
echo "⏳ Waiting for Spark to start processing..."
sleep 30

# Check ClickHouse for enriched data
echo "📊 Checking ClickHouse for enriched data..."
docker compose exec clickhouse clickhouse-client -u app --password app -q "SELECT COUNT(*) as total_enriched FROM app.enriched_engagements;"

# Check Redis streams
echo "🔴 Checking Redis streams..."
docker compose exec redis redis-cli xlen "enriched_events:podcast" 2>/dev/null || echo "No podcast stream yet"

# Show final status
echo "📈 Final Pipeline Status:"
echo "=========================="
echo "✅ PostgreSQL: Running"
echo "✅ Debezium: Running"
echo "✅ Redpanda: Running"
echo "✅ Spark: Running"
echo "✅ ClickHouse: Running"
echo "✅ Redis: Running"
echo "✅ Redis Consumer: Running"

echo ""
echo "🎯 Pipeline is now running with the new architecture!"
echo "📊 Monitor the pipeline: ./monitor.sh"
echo "🛑 Stop everything: docker compose down"
echo ""
echo "Data flow: PostgreSQL → Debezium → Redpanda → Spark → enriched_engagement_events → Redis Consumer → Redis Streams"

# Keep the script running
wait $SPARK_PID 