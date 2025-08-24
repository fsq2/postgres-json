import os
import threading
import time
from pyspark.sql import SparkSession
from pyspark.sql.functions import (
    col,
    from_json,
    to_timestamp,
    when,
    round as sround,
    lit,
    to_json,
    struct,
)
from pyspark.sql.types import (
    StructType,
    StructField,
    StringType,
    IntegerType,
    LongType,
    MapType,
    DoubleType,
)

# ----------------------------
# Debezium value payloads (simplified)
# ----------------------------
content_after_schema = StructType(
    [
        StructField("id", StringType()),  # UUID as string
        StructField("slug", StringType()),
        StructField("title", StringType()),
        StructField("content_type", StringType()),
        StructField("length_seconds", IntegerType()),
        StructField("publish_ts", StringType()),  # will cast later
    ]
)

content_value_schema = StructType(
    [
        StructField("op", StringType()),
        StructField("ts_ms", LongType()),
        StructField("after", content_after_schema),
        StructField("before", content_after_schema),
    ]
)

eng_after_schema = StructType(
    [
        StructField("id", LongType()),  # BIGSERIAL
        StructField("content_id", StringType()),  # UUID as string
        StructField("user_id", StringType()),
        StructField("event_type", StringType()),
        StructField("event_ts", StringType()),  # will cast later
        StructField("duration_ms", IntegerType()),
        StructField("device", StringType()),
        StructField("raw_payload", MapType(StringType(), StringType())),
    ]
)

eng_value_schema = StructType(
    [
        StructField("op", StringType()),
        StructField("ts_ms", LongType()),
        StructField("after", eng_after_schema),
        StructField("before", eng_after_schema),
    ]
)


def log_stream_progress(query, query_name):
    """Log streaming query progress"""
    try:
        progress = query.lastProgress
        if progress:
            batch_id = progress.get("batchId", "N/A")
            input_rate = progress.get("inputRowsPerSecond", 0)
            processing_time = progress.get("durationMs", {}).get("triggerExecution", 0)
            print(
                f"{query_name} - Batch: {batch_id}, "
                f"Input Rate: {input_rate:.2f} rows/sec, "
                f"Processing Time: {processing_time}ms"
            )
    except Exception as e:
        print(f"Error logging progress for {query_name}: {e}")


def main():
    # ------- Kafka / Redpanda -------
    bootstrap = os.getenv("KAFKA_BOOTSTRAP", "redpanda:9092")
    topic_content = os.getenv("TOPIC_CONTENT", "postgres.public.content")
    topic_events = os.getenv("TOPIC_EVENTS", "postgres.public.engagement_events")
    enrich_topic = os.getenv("ENRICH_TOPIC", "enriched_engagement_events")
    starting = os.getenv("STARTING_OFFSETS", "latest")  # or "earliest"

    # ------- ClickHouse (for dim + per-batch join) -------
    ch_host = os.getenv("CLICKHOUSE_HOST", "clickhouse")
    ch_port = int(os.getenv("CLICKHOUSE_PORT", "8123"))
    ch_db = os.getenv("CLICKHOUSE_DB", "app")
    ch_user = os.getenv("CLICKHOUSE_USER", "app")
    ch_pass = os.getenv("CLICKHOUSE_PASSWORD", "app")
    ch_url = f"jdbc:clickhouse://{ch_host}:{ch_port}/{ch_db}"
    ch_props = {
        "user": ch_user,
        "password": ch_pass,
        "driver": "com.clickhouse.jdbc.ClickHouseDriver",
    }

    # ------- Spark session -------
    spark = SparkSession.builder.appName("Redpanda→Enrichment→MultiSink").getOrCreate()
    spark.sparkContext.setLogLevel("WARN")

    print("Starting Spark Streaming Application")
    print(f"Kafka Bootstrap: {bootstrap}")
    print(f"Content Topic: {topic_content}")
    print(f"Events Topic: {topic_events}")
    print(f"Enriched Topic: {enrich_topic}")
    print(f"Starting Offsets: {starting}")

    # Base Kafka configuration with resilience options
    base_kafka = (
        spark.readStream.format("kafka")
        .option("kafka.bootstrap.servers", bootstrap)
        .option("startingOffsets", starting)
        .option("failOnDataLoss", "false")  # Handle offset issues gracefully
        .option("maxOffsetsPerTrigger", "1000")  # Control batch size
        .option("kafka.session.timeout.ms", "30000")  # Increase session timeout
        .option("kafka.request.timeout.ms", "40000")  # Increase request timeout
    )

    # ----------------------------
    # CONTENT stream (upsert to ClickHouse dim)
    # ----------------------------
    print("Setting up content stream...")
    raw_content = base_kafka.option("subscribe", topic_content).load()

    content_rows = (
        raw_content.selectExpr("CAST(value AS STRING) AS json_str")
        .select(from_json(col("json_str"), content_value_schema).alias("j"))
        .select("j.*")
        .where(col("op").isin("c", "u", "r"))  # upserts/snapshots only
        .select(
            col("after.id").alias("id"),
            col("after.slug").alias("slug"),
            col("after.title").alias("title"),
            col("after.content_type").alias("content_type"),
            col("after.length_seconds").alias("length_seconds"),
            to_timestamp(col("after.publish_ts")).alias("publish_ts"),
            col("ts_ms").alias("version_ts_ms"),
        )
    )

    def upsert_content_to_clickhouse(batch_df, batch_id):
        if batch_df.rdd.isEmpty():
            print(f"Content Batch {batch_id}: Empty batch, skipping")
            return

        try:
            count = batch_df.count()
            print(f"Content Batch {batch_id}: Processing {count} content records")

            # Upsert pattern with ReplacingMergeTree (version_ts_ms)
            (
                batch_df.write.mode("append").jdbc(
                    ch_url, "content_dim", properties=ch_props
                )
            )

            print(
                f"Content Batch {batch_id}: Successfully upserted {count} records to ClickHouse"
            )

        except Exception as e:
            print(f"Content Batch {batch_id}: Error upserting to ClickHouse: {e}")
            # In production, you might want to write to a dead letter queue
            # or implement retry logic here
            raise

    content_q = (
        content_rows.writeStream.outputMode("append")
        .option("checkpointLocation", "/opt/app/checkpoints/content_dim")
        .trigger(processingTime="10 seconds")  # Process every 10 seconds
        .foreachBatch(upsert_content_to_clickhouse)
        .start()
    )

    # ----------------------------
    # EVENTS stream → enrich → publish to multiple sinks
    # ----------------------------
    print("Setting up events stream...")
    raw_events = base_kafka.option("subscribe", topic_events).load()

    events_rows = (
        raw_events.selectExpr("CAST(value AS STRING) AS json_str")
        .select(from_json(col("json_str"), eng_value_schema).alias("j"))
        .select("j.*")
        .where(col("op").isin("c", "r"))
        .select(
            col("after.id").alias("event_id"),
            col("after.content_id").alias("content_id"),
            col("after.user_id").alias("user_id"),
            col("after.event_type").alias("event_type"),
            to_timestamp(col("after.event_ts")).alias("event_ts"),
            col("after.duration_ms").alias("duration_ms"),
            col("after.device").alias("device"),
        )
    )

    def write_to_kafka(df, batch_id=None):
        """Prepares and writes a DataFrame to a Kafka topic."""
        try:
            kafka_df = df.select(
                col("content_id").alias("key").cast("string"),
                to_json(struct(*df.columns)).alias("value"),
            )

            (
                kafka_df.write.format("kafka")
                .option("kafka.bootstrap.servers", bootstrap)
                .option("topic", enrich_topic)
                .save()
            )

            count = df.count()
            print(
                f"Batch {batch_id}: Successfully wrote {count} records to Kafka topic: {enrich_topic}"
            )

        except Exception as e:
            print(f"Batch {batch_id}: Error writing to Kafka: {e}")
            raise

    def write_to_clickhouse_facts(df, batch_id=None):
        """Writes the enriched DataFrame to a ClickHouse facts table."""
        try:
            (
                df.write.mode("append").jdbc(
                    ch_url, "enriched_engagements", properties=ch_props
                )
            )

            count = df.count()
            print(
                f"Batch {batch_id}: Successfully wrote {count} records to ClickHouse table: enriched_engagements"
            )

        except Exception as e:
            print(f"Batch {batch_id}: Error writing to ClickHouse facts: {e}")
            raise

    def enrich_and_publish_to_sinks(batch_df, batch_id):
        if batch_df.rdd.isEmpty():
            print(f"Events Batch {batch_id}: Empty batch, skipping")
            return

        try:
            count = batch_df.count()
            print(f"Events Batch {batch_id}: Processing {count} engagement events")

            # 1. Load latest content dim snapshot from ClickHouse
            print(
                f"Events Batch {batch_id}: Loading content dimensions from ClickHouse"
            )
            dim_df = spark.read.jdbc(
                ch_url,
                "(SELECT * FROM app.content_dim FINAL) AS dim",
                properties=ch_props,
            ).select(
                col("id").alias("dim_id"),
                "slug",
                "title",
                "content_type",
                "length_seconds",
                "publish_ts",
            )

            dim_count = dim_df.count()
            print(
                f"Events Batch {batch_id}: Loaded {dim_count} content dimension records"
            )

            # 2. Enrich the event data with content dimensions
            print(f"Events Batch {batch_id}: Enriching events with content dimensions")
            enriched = (
                batch_df.join(dim_df, batch_df.content_id == dim_df.dim_id, "left")
                .withColumn(
                    "engagement_seconds",
                    when(
                        col("duration_ms").isNull(), lit(None).cast(DoubleType())
                    ).otherwise(col("duration_ms") / lit(1000.0)),
                )
                .withColumn(
                    "engagement_percent",
                    when(
                        (col("length_seconds").isNull()) | (col("length_seconds") == 0),
                        lit(None).cast(DoubleType()),
                    ).otherwise(
                        sround(
                            (col("engagement_seconds") / col("length_seconds")) * 100.0,
                            2,
                        )
                    ),
                )
                .select(
                    "event_id",
                    "content_id",
                    "user_id",
                    "event_type",
                    "event_ts",
                    "duration_ms",
                    "device",
                    "engagement_seconds",
                    "engagement_percent",
                    col("slug").alias("content_slug"),
                    col("title").alias("content_title"),
                    col("content_type"),
                    col("length_seconds"),
                    col("publish_ts"),
                )
            )

            enriched_count = enriched.count()
            print(f"Events Batch {batch_id}: Enriched {enriched_count} events")

            # 3. Write to different sinks
            print(f"Events Batch {batch_id}: Writing to sinks...")
            write_to_kafka(enriched, batch_id)
            write_to_clickhouse_facts(enriched, batch_id)

            print(f"Events Batch {batch_id}: Successfully completed processing")

        except Exception as e:
            print(
                f"Events Batch {batch_id}: Error during enrichment and publishing: {e}"
            )
            # In production, implement dead letter queue or retry logic
            raise

    enriched_q = (
        events_rows.writeStream.outputMode("append")
        .option("checkpointLocation", "/opt/app/checkpoints/enriched_multi_sink")
        .trigger(processingTime="10 seconds")  # Process every 10 seconds
        .foreachBatch(enrich_and_publish_to_sinks)
        .start()
    )

    # ----------------------------
    # Stream Monitoring
    # ----------------------------
    def monitor_streams():
        """Monitor streaming queries and log their progress"""
        while True:
            try:
                time.sleep(30)  # Log every 30 seconds

                print("=== Stream Health Check ===")

                if content_q and content_q.isActive:
                    log_stream_progress(content_q, "Content Stream")
                else:
                    print("Content Stream: INACTIVE")

                if enriched_q and enriched_q.isActive:
                    log_stream_progress(enriched_q, "Enriched Events Stream")
                else:
                    print("Enriched Events Stream: INACTIVE")

                # Log active streams count
                active_streams = len([q for q in spark.streams.active if q.isActive])
                print(f"Active Streams: {active_streams}/2")
                print("========================")

            except Exception as e:
                print(f"Error in stream monitoring: {e}")

    # Start monitoring thread
    print("Starting stream monitoring...")
    monitor_thread = threading.Thread(target=monitor_streams, daemon=True)
    monitor_thread.start()

    # ----------------------------
    # Main execution and graceful shutdown
    # ----------------------------
    try:
        print("All streams started successfully!")
        print("Content stream query ID:", content_q.id)
        print("Events stream query ID:", enriched_q.id)
        print("Press Ctrl+C to stop gracefully...")

        # Keep both streams alive
        spark.streams.awaitAnyTermination()

    except KeyboardInterrupt:
        print("\n=== Graceful Shutdown Initiated ===")

        print("Stopping content stream...")
        if content_q and content_q.isActive:
            content_q.stop()
            print("Content stream stopped")

        print("Stopping enriched events stream...")
        if enriched_q and enriched_q.isActive:
            enriched_q.stop()
            print("Enriched events stream stopped")

        print("Stopping Spark session...")
        spark.stop()
        print("Spark session stopped")

        print("=== Shutdown Complete ===")

    except Exception as e:
        print(f"Unexpected error: {e}")

        # Emergency shutdown
        print("=== Emergency Shutdown ===")
        for query in spark.streams.active:
            try:
                query.stop()
            except:
                pass

        try:
            spark.stop()
        except:
            pass

        raise


if __name__ == "__main__":
    main()
