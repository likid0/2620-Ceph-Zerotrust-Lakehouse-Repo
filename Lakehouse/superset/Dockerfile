FROM apache/superset:latest

USER root
RUN uv pip install --no-cache-dir sqlalchemy-trino trino
USER superset
