FROM alpine:3.22.1

ENV CRON_CUSTOM_SCRIPTS_DIR=/opt/cron

# * each script is in bin/
# * each period is one of the directory suffixes listed below (and in crontab)
ENV VACUUMLO_SCRIPT=postgres-vacuum-lo
ENV VACUUMLO_PERIOD=daily

ENV ANALYZE_SCRIPT=postgres-analyze
ENV ANALYZE_PERIOD=daily

COPY crontab /etc/crontabs/root
COPY bin/ $CRON_CUSTOM_SCRIPTS_DIR

RUN mkdir /etc/periodic/1min \
  && mkdir -p /etc/periodic/15min \
  && mkdir -p /etc/periodic/30min \
  && mkdir -p /etc/periodic/hourly \
  && mkdir -p /etc/periodic/12hour \
  && mkdir -p /etc/periodic/daily \
  && mkdir -p /etc/periodic/weekly \
  && mkdir -p /etc/periodic/monthly \
  && mkdir -p $CRON_CUSTOM_SCRIPTS_DIR \
  && chmod -R 755 $CRON_CUSTOM_SCRIPTS_DIR \
  && apk add --no-cache bash postgresql-client postgresql-contrib

ENV VACUUMLO_JOB=/etc/periodic/$VACUUMLO_PERIOD/$VACUUMLO_SCRIPT
RUN cp $CRON_CUSTOM_SCRIPTS_DIR/$VACUUMLO_SCRIPT $VACUUMLO_JOB

ENV ANALYZE_JOB=/etc/periodic/$ANALYZE_PERIOD/$ANALYZE_SCRIPT
RUN cp $CRON_CUSTOM_SCRIPTS_DIR/$ANALYZE_SCRIPT $ANALYZE_JOB

COPY docker-entrypoint.sh /
RUN chmod 755 /docker-entrypoint.sh
ENTRYPOINT ["/docker-entrypoint.sh"]
