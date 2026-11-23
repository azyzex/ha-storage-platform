#!/bin/bash
# glusterd in the background, exporter in the foreground. Stopping the container stops both,
# which Prometheus sees as the target going down (the "node down" signal).

# Stale PID files survive "docker stop/start" (/var/run is in the container layer, /var/lib/glusterd is a
# volume). PIDs restart from small numbers in a fresh container, so an old brick PID can match ANOTHER live
# process (e.g. the self-heal daemon); glusterd then thinks the brick is running and never starts it.
# Found by the load + chaos test: the restarted node's brick stayed offline and nothing could heal.
rm -f /var/run/gluster/*.pid /var/run/gluster/vols/*/*.pid /var/lib/glusterd/vols/*/run/*.pid 2>/dev/null

glusterd -N --log-file=/dev/stdout &

# Safety net, once per start: if this node's brick is still offline after glusterd settled, restart missing
# bricks ("volume start force" only starts bricks that are down; running ones are untouched).
(
  sleep 25
  for vol in $(gluster --mode=script volume list 2>/dev/null); do
    status=$(gluster --mode=script volume status "$vol" "$(hostname):/bricks/$vol" 2>/dev/null | awk '/^Brick/ {print $(NF-1)}')
    if [ "$status" = "N" ]; then
      echo "entrypoint: brick $(hostname):/bricks/$vol offline after start -> volume start $vol force"
      gluster --mode=script volume start "$vol" force
    fi
  done
) &

exec python3 /usr/local/bin/gluster-exporter.py
