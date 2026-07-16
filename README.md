# Local Docker Environment

Docker environment for personal use by developers.

## Prerequisites

* Bash - for running Shell scripts; macOS may ship with an outdated version (3.x) - please install a more recent one
  (at least 4.x) with `brew install bash`
* Docker daemon running (see official installation instructions, for example, for
  [Ubuntu](https://docs.docker.com/engine/install/ubuntu/#install-using-the-convenience-script))

## Main Setup

The working directory for all operations performed in this section is `testproject-local`. To create a local Docker
environment:

* Run `bin/init-env`. It generates `.env` (for Docker Compose).
  Don't commit them to VCS accidentally, they contain secrets! Because of ElasticSearch requirements, the script
  checks if the new password is at least 6 characters long.
* Run `bin/select-services` (on Linux only; for a different OS, please edit `COMPOSE_PROFILES` in the `.env` file
  manually). The script updates `COMPOSE_PROFILES` in interactive mode in order to run only the services that are needed
  at the moment (the full set requires a lot of RAM). Upon confirmation, it stops currently running services and starts
  the selected ones. If the list of services doesn't change, the `bin/stop && bin/start` combo does the same thing.

If `bin/init-env` is run again - after the containers have started at least once - the changes will most likely not be
applied, since some containers are initialized at first launch. To recreate the environment from scratch:

* run `bin/remove-docker-volumes`, which **erases all accumulated data** (Docker volumes)
* delete `.env` file
* run `bin/init-env`

The `/bin` directory contains the following scripts for managing the environment:

* `init-env` - creates local Docker environment
* `select-services` - selects and restarts services in interactive mode (for Linux only)
* `start` - starts services listed in `COMPOSE_PROFILES`
* `stop` - stops services listed in `COMPOSE_PROFILES`
* `ps` - displays list of running services
* `logs` - displays logs of services passed as arguments, for example: `logs redis`
* `shell` - enters Shell terminal of service passed as argument, for example: `shell redis`
* `shell-root` - same as `shell`, but with superuser (root) privileges
* `remove-docker-volumes` - stops services listed in `COMPOSE_PROFILES` and **erases their data** (Docker volumes)
* `ctop` - displays CPU/RAM used by services, in interactive mode
* `check-image-versions` - checks if newer Docker image versions are available on Docker Hub

## Docker Containers

In order to save RAM on your computer, memory limits have been tightened for all containers to such extent that they do
not crash.

Make sure ports published by the containers aren't being used by other software, otherwise the containers can't start.
To enable/disable service groups, see `COMPOSE_PROFILES` in `.env` file. Each service accepts the same user credentials
(those entered in `bin/init-env` script) unless otherwise specified.

* **Databases**
    * **Postgres**
        * Postgres - port 5432; actually
          it's [TimescaleDB-HA](https://github.com/timescale/timescaledb-docker-ha)
        * Postgres Maintenance - runs periodic jobs to purge unused data (deleted rows, LOBs) and optimize indexes
    * **Mongo** - port 27017
    * **Redis** - port 6379
* **Kafka**
    * Kafka - port 9092
    * web UI - port [8092](http://localhost:8092)
* **Keycloak** - port [8401](http://localhost:8401)
