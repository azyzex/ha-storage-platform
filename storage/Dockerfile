# GlusterFS server node + per-node Prometheus exporter. Same Ubuntu release as the client on the host
# (24.04 -> GlusterFS 11.x), so client and server versions match. python3 is also needed by Ansible.
FROM ubuntu:24.04
RUN apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      glusterfs-server procps iproute2 python3 python3-prometheus-client \
 && rm -rf /var/lib/apt/lists/*
COPY exporter.py /usr/local/bin/gluster-exporter.py
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh
# Bricks live under /bricks (a Docker volume on the host's ext4, which supports the trusted.* xattrs Gluster needs).
VOLUME ["/bricks", "/var/lib/glusterd"]
EXPOSE 24007 9713
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
