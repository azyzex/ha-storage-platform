# GlusterFS server node. Same Ubuntu release as the client on the host (24.04 -> GlusterFS 11.x),
# so client and server versions match.
FROM ubuntu:24.04
RUN apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends glusterfs-server procps iproute2 \
 && rm -rf /var/lib/apt/lists/*
# Bricks live under /bricks (a Docker volume on the host's ext4, which supports the trusted.* xattrs Gluster needs).
VOLUME ["/bricks", "/var/lib/glusterd"]
# -N keeps glusterd in the foreground so the container lives as long as the daemon.
CMD ["glusterd", "-N", "--log-file=/dev/stdout"]
