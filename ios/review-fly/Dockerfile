FROM debian:bookworm-slim

ARG TARGETARCH

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        bash ca-certificates curl git jq openssh-server tini util-linux \
    && rm -rf /var/lib/apt/lists/* \
    && useradd --home-dir /data/home/review --shell /bin/sh review \
    && mkdir -p /run/sshd

# One desired-state manifest owns versions and publisher checksums for both architectures.
# Keep the bundle outside /data: Fly mounts the existing volume over that path.
COPY runtime.env pi-settings.json /opt/review/
COPY install-runtime.sh configure-home.sh verify-runtime.sh /opt/review/scripts/
RUN sh /opt/review/scripts/install-runtime.sh "$TARGETARCH" \
    && chmod 755 /opt/review/scripts/verify-runtime.sh \
    && ln -s /opt/review/scripts/verify-runtime.sh /usr/local/bin/review-verify

COPY sshd_config /etc/ssh/sshd_config
COPY entrypoint.sh /usr/local/bin/review-entrypoint
RUN chmod 755 /usr/local/bin/review-entrypoint

ENV TERM=xterm-256color
ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/review-entrypoint"]
