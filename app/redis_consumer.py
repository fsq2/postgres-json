#!/usr/bin/env python3
"""
Redis Consumer for Enriched Engagement Events
Reads from Kafka topic 'enriched_engagement_events' and writes to Redis streams
"""

import json
import os
import time
import redis
from kafka import KafkaConsumer
from datetime import datetime

def main():
    # Configuration
    kafka_bootstrap = os.getenv("KAFKA_BOOTSTRAP", "localhost:19092")
    kafka_topic = os.getenv("ENRICH_TOPIC", "enriched_engagement_events")
    redis_host = os.getenv("REDIS_HOST", "localhost")
    redis_port = int(os.getenv("REDIS_PORT", "6379"))
    
    print(f"Starting Redis Consumer...")
    print(f"Kafka: {kafka_bootstrap}")
    print(f"Topic: {kafka_topic}")
    print(f"Redis: {redis_host}:{redis_port}")
    
    # Initialize Kafka consumer
    consumer = KafkaConsumer(
        kafka_topic,
        bootstrap_servers=[kafka_bootstrap],
        auto_offset_reset='latest',
        enable_auto_commit=True,
        group_id='redis-consumer-group',
        value_deserializer=lambda x: json.loads(x.decode('utf-8'))
    )
    
    # Initialize Redis connection
    r = redis.Redis(
        host=redis_host, 
        port=redis_port, 
        db=0, 
        decode_responses=True,
        socket_connect_timeout=5,
        socket_timeout=5
    )
    
    # Test Redis connection
    try:
        r.ping()
        print("✅ Redis connection successful")
    except Exception as e:
        print(f"❌ Redis connection failed: {e}")
        return
    
    # Test Kafka connection
    try:
        consumer.topics()
        print("✅ Kafka connection successful")
    except Exception as e:
        print(f"❌ Kafka connection failed: {e}")
        return
    
    print(f"🚀 Consumer started. Waiting for messages from topic: {kafka_topic}")
    
    # Main consumption loop
    try:
        for message in consumer:
            try:
                # Parse the enriched event data
                event_data = message.value
                
                # Create Redis stream key based on content type
                content_type = event_data.get('content_type', 'unknown')
                stream_key = f"enriched_events:{content_type}"
                
                # Prepare data for Redis stream
                stream_data = {
                    'event_id': str(event_data.get('event_id', '')),
                    'content_id': str(event_data.get('content_id', '')),
                    'user_id': str(event_data.get('user_id', '')),
                    'event_type': str(event_data.get('event_type', '')),
                    'event_ts': str(event_data.get('event_ts', '')),
                    'engagement_percent': str(event_data.get('engagement_percent', '')),
                    'content_title': str(event_data.get('content_title', '')),
                    'device': str(event_data.get('device', '')),
                    'processed_at': datetime.now().isoformat()
                }
                
                # Add to Redis stream
                stream_id = r.xadd(stream_key, stream_data, maxlen=1000)
                
                # Update real-time aggregations
                update_realtime_aggregations(r, event_data)
                
                print(f"✅ Processed event {event_data.get('event_id')} -> Redis stream {stream_key}")
                
            except Exception as e:
                print(f"❌ Error processing message: {e}")
                continue
                
    except KeyboardInterrupt:
        print("\n🛑 Consumer stopped by user")
    except Exception as e:
        print(f"❌ Consumer error: {e}")
    finally:
        consumer.close()
        r.close()

def update_realtime_aggregations(r, event_data):
    """Update real-time aggregations in Redis"""
    try:
        content_id = event_data.get('content_id')
        engagement_percent = event_data.get('engagement_percent')
        content_type = event_data.get('content_type', 'unknown')
        
        if content_id and engagement_percent is not None:
            # Update top engaging content (last 10 minutes)
            top_content_key = f"top_engaging_content:{content_type}"
            
            # Add to sorted set with timestamp as score
            timestamp = int(time.time())
            r.zadd(top_content_key, {content_id: engagement_percent})
            
            # Keep only last 10 minutes of data
            cutoff_time = timestamp - 600  # 10 minutes
            r.zremrangebyscore(top_content_key, 0, cutoff_time)
            
            # Keep only top 100 items
            r.zremrangebyrank(top_content_key, 0, -101)
            
            # Set TTL to 1 hour
            r.expire(top_content_key, 3600)
            
            # Update content engagement summary
            summary_key = f"content_summary:{content_id}"
            r.hset(summary_key, mapping={
                'last_event_ts': str(event_data.get('event_ts', '')),
                'last_engagement_percent': str(engagement_percent),
                'content_title': str(event_data.get('content_title', '')),
                'content_type': str(content_type),
                'updated_at': str(datetime.now().isoformat())
            })
            r.expire(summary_key, 86400)  # 24 hours TTL
            
    except Exception as e:
        print(f"Warning: Failed to update aggregations: {e}")

if __name__ == "__main__":
    main() 