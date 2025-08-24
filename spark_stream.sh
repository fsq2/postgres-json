docker compose exec spark-master bash -lc '
  /opt/bitnami/spark/bin/spark-submit \
    --packages org.apache.spark:spark-sql-kafka-0-10_2.12:3.4.1 \
    /opt/app/stream.py
'