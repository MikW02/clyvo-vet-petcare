# Custom Oracle image for Clyvo-vet PetCare.
# Based on gvenzl/oracle-free which is the officially recommended community
# image for Oracle Database Free Edition. We layer our own init SQL so the
# `clyvo` schema is provisioned on the very first container start.

FROM gvenzl/oracle-xe:21-slim-faststart

# Default credentials (override at `docker run` time with -e).
ENV ORACLE_PASSWORD=oracle123 \
    APP_USER=clyvo \
    APP_USER_PASSWORD=clyvo123

# Anything placed in /container-entrypoint-initdb.d runs once, the first time
# the named volume mounted at /opt/oracle/oradata is empty.
COPY init/01_schema.sql /container-entrypoint-initdb.d/01_schema.sql

EXPOSE 1521

# Oracle Free needs ≥1G of /dev/shm; users running `docker run` directly should
# pass `--shm-size=2g`. The provided run-local scripts already do.
