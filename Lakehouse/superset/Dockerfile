FROM docker.io/apache/superset:v5.0.0

USER root

# Ensure uv is available
RUN pip install --no-cache-dir uv

# Install the Trino connector directly into the environment used by Superset
RUN uv pip install --no-cache-dir sqlalchemy-trino trino

USER superset

