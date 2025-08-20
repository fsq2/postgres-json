from pyspark.sql import SparkSession

# 1. Create a SparkSession
# The appName is just a name for your application.
spark = SparkSession.builder.appName("DebeziumConsolePrinter").getOrCreate()

# Set log level to WARN to reduce verbosity
spark.sparkContext.setLogLevel("WARN")

# 2. Read from the Redpanda (Kafka) topic
# The topic name 'dbz.postgres.public.orders' is derived from your Debezium config:
# topic.prefix (dbz) + database.server.name (postgres) + table name (public.orders)
kafka_df = (
    spark.readStream.format("kafka")
    .option("kafka.bootstrap.servers", "redpanda:9092")
    .option("subscribe", "dbz.postgres.public.engagement_events")
    .option("startingOffsets", "earliest")
    .load()
)

# 3. Process the data
# Kafka messages have a 'value' column containing the data in binary format.
# We cast it to a string to see the raw JSON from Debezium.
string_df = kafka_df.selectExpr("CAST(value AS STRING)")

# 4. Print the output to the console
# This sets up a "console" sink that prints every message received from the topic.
# 'truncate=false' ensures you see the entire long JSON message without it being cut off.
query = (
    string_df.writeStream.outputMode("append")
    .format("console")
    .option("truncate", "false")
    .start()
)

# 5. Wait for the stream to terminate
query.awaitTermination()
