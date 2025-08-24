FROM bitnami/spark:3.4.1

# Switch to root to install system packages
USER root

# Update package lists and install Python3 + dependencies
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        python3 \
        python3-pip \
        python3-dev \
        wget \
        curl && \
    rm -rf /var/lib/apt/lists/*

# Create symlinks for python and pip (ensure they point to python3)
RUN update-alternatives --install /usr/bin/python python /usr/bin/python3 1 && \
    update-alternatives --install /usr/bin/pip pip /usr/bin/pip3 1

# Verify Python installation
RUN python --version && pip --version && which python && which pip

# Download ClickHouse JDBC driver into Spark's classpath
RUN wget -O /opt/bitnami/spark/jars/clickhouse-jdbc.jar \
    https://repo1.maven.org/maven2/com/clickhouse/clickhouse-jdbc/0.3.2-patch11/clickhouse-jdbc-0.3.2-patch11.jar

# Copy your application code
COPY app/ /opt/app/
RUN chown -R 1001:1001 /opt/app

# Back to non-root user (Bitnami expects UID 1001)
USER 1001

# Ensure Spark uses Python 3 for both driver and executors
ENV PYSPARK_PYTHON=/usr/bin/python3 \
    PYSPARK_DRIVER_PYTHON=/usr/bin/python3

# No CMD here: keep Bitnami's entrypoint behavior