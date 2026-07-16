#!/bin/sh

# -f : run in foreground
# -l, -d: log levels (8 means verbose)
# -L: log file
crond -f -l 8 -d 8 -L /dev/stdout
