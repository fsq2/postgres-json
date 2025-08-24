#!/bin/bash

echo "🔍 Monitoring PostgreSQL CDC Pipeline..."

echo -e "\n📊 Docker Compose Status:"
docker compose ps

echo -e "\n🔌 Debezium Connector Status:"
docker compose exec debezium curl -s debezium:8083/connectors/postgres-connector/status 2>/dev/null | jq . || echo "Connector not found or not running"

echo -e "\n📋 Redpanda Topics:"
docker compose exec redpanda rpk topic list 2>/dev/null || echo "Redpanda not accessible"

echo -e "\n📈 Topic Details (if accessible):"
docker compose exec redpanda rpk topic describe postgres.public.content 2>/dev/null || echo "Topic postgres.public.content not found"
docker compose exec redpanda rpk topic describe postgres.public.engagement_events 2>/dev/null || echo "Topic postgres.public.engagement_events not found"

echo -e "\n🗄️ PostgreSQL Tables:"
docker compose exec postgres psql -U postgresuser -d pandashop -c "\dt" 2>/dev/null || echo "PostgreSQL not accessible"

echo -e "\n📊 PostgreSQL Row Counts:"
docker compose exec postgres psql -U postgresuser -d pandashop -c "SELECT 'content' as table_name, COUNT(*) as count FROM content UNION ALL SELECT 'engagement_events', COUNT(*) FROM engagement_events;" 2>/dev/null || echo "PostgreSQL not accessible"

echo -e "\n🏗️ ClickHouse Tables:"
docker compose exec clickhouse clickhouse-client -u app --password app -q "SHOW TABLES FROM app" 2>/dev/null || echo "ClickHouse not accessible"

echo -e "\n📊 ClickHouse Row Counts:"
docker compose exec clickhouse clickhouse-client -u app --password app -q "SELECT 'content_dim' as table_name, COUNT(*) as count FROM app.content_dim UNION ALL SELECT 'enriched_engagements', COUNT(*) FROM app.enriched_engagements;" 2>/dev/null || echo "ClickHouse not accessible"

echo -e "\n🔴 Redis Status:"
docker compose exec redis redis-cli ping 2>/dev/null || echo "Redis not accessible"

echo -e "\n📝 Recent Logs (last 10 lines):"
echo "PostgreSQL:"
docker compose logs postgres --tail=10 2>/dev/null || echo "No logs available"
echo "Redpanda:"
docker compose logs redpanda --tail=10 2>/dev/null || echo "No logs available"
echo "Debezium:"
docker compose logs debezium --tail=10 2>/dev/null || echo "No logs available" 