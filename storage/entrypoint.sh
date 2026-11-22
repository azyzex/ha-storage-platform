#!/bin/bash
# glusterd in the background, exporter in the foreground. Stopping the container stops both,
# which Prometheus sees as the target going down (the "node down" signal).
glusterd -N --log-file=/dev/stdout &
exec python3 /usr/local/bin/gluster-exporter.py
