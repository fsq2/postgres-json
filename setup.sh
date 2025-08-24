#!/bin/bash

echo "🚀 Setting up PostgreSQL CDC to Redpanda to Spark to ClickHouse/Redis pipeline..."

# Start all services
echo "📦 Starting Docker Compose services..."
docker compose up -d

# Wait for services to be healthy
echo "⏳ Waiting for services to be healthy..."
sleep 30

# Create Debezium connector
echo "🔌 Creating Debezium PostgreSQL connector..."
./create_debezium_postgres_connector.sh

# Wait for connector to be ready
echo "⏳ Waiting for connector to be ready..."
sleep 10

# Check connector status
echo "📊 Checking connector status..."
docker compose exec debezium curl -s debezium:8083/connectors/postgres-connector/status | jq .

# Check if topics are created
echo "📋 Checking Redpanda topics..."
docker compose exec redpanda rpk topic list

# Insert test data
echo "🧪 Inserting test data..."
docker compose exec postgres psql -U postgresuser -d pandashop -c "
INSERT INTO content (id, slug, title, content_type, length_seconds, publish_ts) VALUES
('550e8400-e29b-41d4-a716-446655440000', 'test-episode', 'Test Episode', 'podcast', 1200, NOW())
ON CONFLICT (id) DO NOTHING;

INSERT INTO engagement_events (content_id, user_id, event_type, event_ts, duration_ms, device, raw_payload) VALUES
('550e8400-e29b-41d4-a716-446655440000', '550e8400-e29b-41d4-a716-446655440001', 'play', NOW(), 30000, 'web', '{\"source\": \"test\"}')
ON CONFLICT (id) DO NOTHING;
"

echo "✅ Setup complete! You can now run the Spark streaming job:"
echo "   ./spark_stream.sh" 