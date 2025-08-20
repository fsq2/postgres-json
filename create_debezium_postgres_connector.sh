#! /bin/bash

docker compose exec debezium `curl -H 'Content-Type: application/json' debezium:8083/connectors --data '
{
  "name": "postgres-connector-content-events",  
  "config": {
    "connector.class": "io.debezium.connector.postgresql.PostgresConnector", 
    "plugin.name": "pgoutput",
    "database.hostname": "postgres", 
    "database.port": "5432", 
    "database.user": "postgresuser", 
    "database.password": "postgrespw", 
    "database.dbname" : "pandashop", 
    "database.server.name": "postgres", 
    "table.include.list": "public.content,public.engagement_events",
    "topic.prefix" : "dbz"
  }
}'