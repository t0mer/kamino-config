#!/usr/bin/env bash
# Write a small login banner. Idempotent: the tools/motd item's check reads
# /etc/motd.kamino and skips the step once this marker file exists.
set -euo pipefail

cat > /etc/motd.kamino <<'EOF'
────────────────────────────────────────
  Provisioned by Kamino
  https://github.com/t0mer/kamino
────────────────────────────────────────
EOF

echo "wrote /etc/motd.kamino"
