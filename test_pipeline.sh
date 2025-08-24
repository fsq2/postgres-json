#!/bin/bash

echo "🧪 Testing PostgreSQL CDC Pipeline..."

# Test 1: Check if all services are running
echo -e "\n1️⃣ Checking service status..."
docker compose ps

# Test 2: Check Debezium connector
echo -e "\n2️⃣ Testing Debezium connector..."
CONNECTOR_STATUS=$(docker compose exec debezium curl -s debezium:8083/connectors/postgres-connector/status 2>/dev/null | jq -r '.connector.state' 2>/dev/null)
if [ "$CONNECTOR_STATUS" = "RUNNING" ]; then
    echo "✅ Debezium connector is RUNNING"
else
    echo "❌ Debezium connector status: $CONNECTOR_STATUS"
fi

# Test 3: Check Redpanda topics
echo -e "\n3️⃣ Testing Redpanda topics..."
TOPICS=$(docker compose exec redpanda rpk topic list 2>/dev/null | grep -E "postgres\.public\.(content|engagement_events)" | wc -l)
if [ "$TOPICS" -eq 2 ]; then
    echo "✅ Both PostgreSQL topics found"
else
    echo "❌ Found $TOPICS topics, expected 2"
fi

# Test 4: Insert test data
echo -e "\n4️⃣ Inserting test data..."
docker compose exec postgres psql -U postgresuser -d pandashop -c "
INSERT INTO content (id, slug, title, content_type, length_seconds, publish_ts) VALUES
('550e8400-e29b-41d4-a716-446655440000', 'test-episode-$(date +%s)', 'Test Episode $(date +%s)', 'podcast', 1200, NOW())
ON CONFLICT (id) DO NOTHING;

INSERT INTO engagement_events (content_id, user_id, event_type, event_ts, duration_ms, device, raw_payload) VALUES
('550e8400-e29b-41d4-a716-446655440000', '550e8400-e29b-41d4-a716-446655440001', 'play', NOW(), 30000, 'web', '{\"source\": \"test\"}')
ON CONFLICT (id) DO NOTHING;
" 2>/dev/null

# Test 5: Check if data appears in Redpanda
echo -e "\n5️⃣ Checking if data appears in Redpanda..."
sleep 5
TOPIC_DATA=$(docker compose exec redpanda rpk topic consume postgres.public.content --num 1 --timeout 10s 2>/dev/null | grep -c "test-episode" || echo "0")
if [ "$TOPIC_DATA" -gt 0 ]; then
    echo "✅ Data successfully captured in Redpanda topic"
else
    echo "❌ No test data found in Redpanda topic"
fi

# Test 6: Check ClickHouse connectivity
echo -e "\n6️⃣ Testing ClickHouse connectivity..."
CH_TEST=$(docker compose exec clickhouse clickhouse-client -u app --password app -q "SELECT 1" 2>/dev/null)
if [ "$CH_TEST" = "1" ]; then
    echo "✅ ClickHouse is accessible"
else
    echo "❌ ClickHouse is not accessible"
fi

# Test 7: Check Redis connectivity
echo -e "\n7️⃣ Testing Redis connectivity..."
REDIS_TEST=$(docker compose exec redis redis-cli ping 2>/dev/null)
if [ "$REDIS_TEST" = "PONG" ]; then
    echo "✅ Redis is accessible"
else
    echo "❌ Redis is not accessible"
fi

# Test 8: Check PostgreSQL connectivity
echo -e "\n8️⃣ Testing PostgreSQL connectivity..."
PG_TEST=$(docker compose exec postgres psql -U postgresuser -d pandashop -c "SELECT COUNT(*) FROM content;" 2>/dev/null | grep -E "^[0-9]+$" | head -1)
if [ -n "$PG_TEST" ] && [ "$PG_TEST" -ge 0 ]; then
    echo "✅ PostgreSQL is accessible, content table has $PG_TEST rows"
else
    echo "❌ PostgreSQL is not accessible"
fi

echo -e "\n🎯 Pipeline Test Summary:"
echo "If you see mostly ✅ marks, your pipeline is working correctly!"
echo "If you see ❌ marks, check the troubleshooting section in README.md"
echo ""
echo "Next steps:"
echo "1. Run the Spark streaming job: ./spark_stream.sh"
echo "2. Monitor the pipeline: ./monitor.sh"
echo "3. Insert more test data to see the full flow" 