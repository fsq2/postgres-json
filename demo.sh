#!/bin/bash

echo "🎬 PostgreSQL CDC Pipeline Demo"
echo "================================"

# Step 1: Start everything
echo -e "\n🚀 Step 1: Starting the pipeline..."
./setup.sh

# Step 2: Wait for everything to be ready
echo -e "\n⏳ Step 2: Waiting for services to be ready..."
sleep 45

# Step 3: Test the pipeline
echo -e "\n🧪 Step 3: Testing the pipeline..."
./test_pipeline.sh

# Step 4: Show the data flow
echo -e "\n📊 Step 4: Demonstrating data flow..."

echo -e "\n📝 Inserting sample data into PostgreSQL..."
docker compose exec postgres psql -U postgresuser -d pandashop -c "
INSERT INTO content (id, slug, title, content_type, length_seconds, publish_ts) VALUES
('demo-$(date +%s)', 'demo-episode-$(date +%s)', 'Demo Episode $(date +%s)', 'video', 1800, NOW())
ON CONFLICT (id) DO NOTHING;

INSERT INTO engagement_events (content_id, user_id, event_type, event_ts, duration_ms, device, raw_payload) VALUES
('demo-$(date +%s)', 'demo-user-$(date +%s)', 'play', NOW(), 45000, 'mobile', '{\"source\": \"demo\", \"campaign\": \"test\"}')
ON CONFLICT (id) DO NOTHING;
"

echo -e "\n⏳ Waiting for data to flow through the pipeline..."
sleep 10

# Step 5: Show data in each component
echo -e "\n🔍 Step 5: Data in each component..."

echo -e "\n📋 Redpanda Topics:"
docker compose exec redpanda rpk topic list | grep postgres

echo -e "\n📊 PostgreSQL Data:"
docker compose exec postgres psql -U postgresuser -d pandashop -c "SELECT id, slug, title FROM content ORDER BY publish_ts DESC LIMIT 3;"

echo -e "\n📈 ClickHouse Data:"
docker compose exec clickhouse clickhouse-client -u app --password app -q "SELECT COUNT(*) as total_content FROM app.content_dim;"
docker compose exec clickhouse clickhouse-client -u app --password app -q "SELECT COUNT(*) as total_events FROM app.enriched_engagements;"

echo -e "\n🔴 Redis Streams:"
docker compose exec redis redis-cli xlen enriched_events

echo -e "\n🎯 Step 6: Starting Spark Streaming (this will run continuously)..."
echo "Press Ctrl+C to stop the demo"
echo ""

# Start Spark streaming in background
./spark_stream.sh &
SPARK_PID=$!

# Wait a bit for Spark to start
sleep 15

# Show final status
echo -e "\n📊 Final Pipeline Status:"
./monitor.sh

echo -e "\n✅ Demo complete! The pipeline is now running."
echo "To stop everything: docker compose down -v"
echo "To view logs: docker compose logs -f [service-name]"
echo "To monitor: ./monitor.sh"

# Wait for user to stop
wait $SPARK_PID 