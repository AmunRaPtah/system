#!/bin/sh
# Deploy the architect server to /opt/architect, (re)start the unit, install cron lines.
# Idempotent. Run as root from anywhere: sh server/deploy.sh
set -eu
SRC=$(cd "$(dirname "$0")" && pwd)
DEST=/opt/architect
mkdir -p "$DEST" /root/.architect
chmod 700 /root/.architect
rsync -a --delete --exclude '__pycache__' --exclude '.pytest_cache' \
  "$SRC/architect" "$SRC/architect_digest.py" "$SRC/requirements.txt" "$DEST/"
if [ ! -s /root/.architect/token ]; then
  umask 077; python3 -c 'import secrets; print(secrets.token_urlsafe(32))' > /root/.architect/token
fi
chmod 600 /root/.architect/token
install -m 644 "$SRC/architect.service" /etc/systemd/system/architect.service
systemctl daemon-reload
systemctl enable architect.service >/dev/null 2>&1
systemctl restart architect.service
# Cron: replace our tagged lines, keep everything else untouched.
TAG='# system-architect'
LOG=/root/.architect/digest.log
{ crontab -l 2>/dev/null | grep -v "$TAG" || true
  echo "30 7 * * * /usr/bin/python3 $DEST/architect_digest.py morning >> $LOG 2>&1 $TAG"
  echo "0 21 * * * /usr/bin/python3 $DEST/architect_digest.py evening >> $LOG 2>&1 $TAG"
  echo "0 12 * * * /usr/bin/python3 $DEST/architect_digest.py check >> $LOG 2>&1 $TAG"
} | crontab -
echo "deployed to $DEST"
