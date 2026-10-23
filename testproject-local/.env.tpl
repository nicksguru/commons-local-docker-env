PROJECT=$PROJECT

#
# Start only some of the services. Shareable services, such as Keycloak/ClickHouse, are supposed to reside on a
# dedicated server.
#
# NOTE: stopping the services is subject to profiles too, i.e. only such services will be stopped that are mentioned
# in COMPOSE_PROFILES.
#
COMPOSE_PROFILES=postgres,mongodb,redis,kafka

#############################################################################

# all possible profiles, please don't modify
ALL_COMPOSE_PROFILES=postgres,mongodb,redis,kafka,keycloak

#############################################################################
# each xx_VERSION variable is prefixed with '#TAG: image_url' and optional multiple '# INFO/WARNING/ERROR: message'

# TAG: https://hub.docker.com/r/timescale/timescaledb-ha/tags
# INFO: keep version number in sync with TestContainers
POSTGRES_IMAGE_VERSION=pg18.6-ts2.31.0

# inside Docker
SQL_HOST=postgres
# outside Docker
SQL_PORT=5432
# auto-create DB and credentials for it (for Postgres, root user is SQL_USER by design)
SQL_DATABASE=${DEFAULT_USERNAME}
SQL_USER=${DEFAULT_USERNAME}
SQL_PASSWORD=${DEFAULT_PASSWORD}

# auto-create DBs for SQL_USER
SQL_KEYCLOAK_DATABASE=keycloak
SQL_UPTRACE_DATABASE=uptrace
#
SQL_VAULT_DATABASE=vault
# same for all DB plugins (otherwise in MySQL the table is not the same as in Postgres)
SQL_VAULT_TABLE=vault_kv_store

#############################################################################

# TAG: https://hub.docker.com/_/mongo/tags
# WARNING: crashes on Linux kernels 6.19-7.0.13 (https://jira.mongodb.org/browse/SERVER-125742)
# INFO: the license is SSPL (AGPLv3 with amendments for cloud providers)
MONGO_IMAGE_VERSION=9.0.4

MONGO_REPLICASET_NAME=rs0
# must be on a volume
MONGO_REPLICASET_KEYFILE=/data/router/replicaset.key
# host names
MONGO_REPLICASET_SHARD1_NODE1=mongodb

# auto-create DB and credentials for it
MONGODB_DATABASE=${DEFAULT_USERNAME}
MONGODB_USERNAME=${DEFAULT_USERNAME}
MONGODB_PASSWORD=${DEFAULT_PASSWORD}

#############################################################################

# TAG: https://hub.docker.com/_/redis/tags
# INFO: starting with v8.0, the license reverted to AGPLv3
# INFO: keep version number in sync with TestContainers
REDIS_IMAGE_VERSION=8.10.2-alpine

REDIS_HOST=redis
REDIS_PORT=6379
REDIS_PASSWORD=${DEFAULT_PASSWORD}
# passed to --appendonly: 'yes' / 'no'
REDIS_PERSISTENCE=yes

#############################################################################

# TAG: https://hub.docker.com/r/tchiotludo/akhq/tags
AKHQ_IMAGE_VERSION=0.28.0

# TAG: https://hub.docker.com/r/confluentinc/cp-kafka/tags
KAFKA_IMAGE_VERSION=8.3.2

# let subscribers create topics
KAFKA_AUTO_CREATE_TOPICS_ENABLE=true

# Default is 1, but then if leader goes down before a message is replicated, the message is lost, so maybe 2?. But if 2,
# if only one node remains, it will not be able to serve requests, yet the goal is to keep working in any case.
# See https://jack-vanlightly.com/blog/2018/9/14/how-to-lose-messages-on-a-kafka-cluster-part1 or
# https://blog.softwaremill.com/help-kafka-ate-my-data-ae2e5d3e6576.
KAFKA_MIN_INSYNC_REPLICAS=1
TRANSACTION_STATE_LOG_MIN_ISR=1

# default is 32Kb which yields too small throughput
KAFKA_RECEIVE_BUFFER_BYTES=1000000

# https://docs.confluent.io/platform/current/installation/configuration/topic-configs.html#message.timestamp.difference.max.ms
# (prevent in-the-future messages from preventing topic compaction)
KAFKA_MESSAGE_TIMESTAMP_DIFFERENCE_MAX_MS=86400000

# Default number of log partitions per topic: it's better to 'overprovision' this, to avoid repartitioning in future.
# NOTE: a value greater than 1 can break certain consumers which rely on the global order of messages
# (this setting applies to auto-creation of new topics only).
KAFKA_NUM_PARTITIONS=1

# 14 days (default is 7 days)
KAFKA_LOG_RETENTION_MS=1209600000
# 60 sec. (default is 10 sec.)
KAFKA_SESSION_TIMEOUT_MS=60000
# 15 sec. (default is 3 sec.)
KAFKA_HEARTBEAT_INTERVAL_MS=15000

KAFKA_CLUSTER_ID=${PROJECT}-local
KAFKA1_EXTERNAL_PORT=9092
KAFKA1_INTERNAL_PORT=9192
KAFKA1_CONTROLLER_PORT=9292

#############################################################################

# TAG: https://hub.docker.com/r/keycloak/keycloak/tags
KEYCLOAK_IMAGE_VERSION=26.8.1-0
KEYCLOAK_ADMIN=${DEFAULT_USERNAME}
KEYCLOAK_ADMIN_PASSWORD=${DEFAULT_PASSWORD}
