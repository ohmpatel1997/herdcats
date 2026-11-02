#!/bin/sh
set -eu

if [ -z "${REVIEW_SSH_PASSWORD:-}" ]; then
    echo "REVIEW_SSH_PASSWORD must be set as a Fly secret" >&2
    exit 1
fi

install -d -m 700 /data/ssh
if [ ! -s /data/ssh/ssh_host_ed25519_key ]; then
    ssh-keygen -q -t ed25519 -N '' -f /data/ssh/ssh_host_ed25519_key
fi
chmod 600 /data/ssh/ssh_host_ed25519_key
chmod 644 /data/ssh/ssh_host_ed25519_key.pub

install -d -o review -g review -m 700 /data/home/review
install -d -o review -g review -m 700 /data/home/review/projects
printf 'review:%s\n' "$REVIEW_SSH_PASSWORD" | chpasswd
unset REVIEW_SSH_PASSWORD

# Refresh the managed helper/extension even when /data contains an older setup.
# Run as review so files have the same owner as Pi and SSH; preserve auth/history.
runuser -u review -- /bin/sh /opt/review/scripts/configure-home.sh /opt/review /data/home/review
runuser -u review -- /usr/local/bin/review-verify /data/home/review

install -d -m 755 /run/sshd
/usr/sbin/sshd -t

shutdown() {
    [ -z "${ssh_pid:-}" ] || kill "$ssh_pid" 2>/dev/null || true
    [ -z "${herdr_pid:-}" ] || kill "$herdr_pid" 2>/dev/null || true
    [ -z "${ssh_pid:-}" ] || wait "$ssh_pid" 2>/dev/null || true
    [ -z "${herdr_pid:-}" ] || wait "$herdr_pid" 2>/dev/null || true
}
trap shutdown INT TERM EXIT

/usr/sbin/sshd -D -e &
ssh_pid=$!
runuser -u review -- /usr/local/bin/herdr server &
herdr_pid=$!

# Exit if either required service dies; Fly can then restart the Machine.
while kill -0 "$ssh_pid" 2>/dev/null && kill -0 "$herdr_pid" 2>/dev/null; do
    sleep 2
done
echo "SSH or Herdr stopped" >&2
exit 1
