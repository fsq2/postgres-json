FROM python:3-alpine
USER root
RUN adduser -D muser
RUN apk update && apk add bash && apk add openjdk11
RUN pip install pyspark

# This is the corrected line
RUN wget https://archive.apache.org/dist/spark/spark-3.3.0/spark-3.3.0-bin-hadoop3.tgz -P /home/muser

RUN cd /home/muser && tar -xzvf /home/muser/spark-3.3.0-bin-hadoop3.tgz
RUN chmod a+x /home/muser/spark-3.3.0-bin-hadoop3/bin/spark-submit
USER muser
ENTRYPOINT ["/home/muser/spark-3.3.0-bin-hadoop3/bin/spark-submit","--packages","org.apache.spark:spark-sql-kafka-0-10_2.12:3.3.0","/home/muser/streamer.py"]