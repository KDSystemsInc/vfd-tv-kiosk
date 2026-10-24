#!/bin/bash
# Publish a signed release. Kiosks pick it up within 6 hours.
#   ./release.sh 1.2.1
# Signs manifest.json with the private key in the macOS Keychain (service kds-kiosk-signing);
# kiosks refuse any release that key did not sign. Prints the one-time bootstrap line for new kiosks.
set -euo pipefail
v=${1:?usage: release.sh <version, e.g. 1.2.1>}
cd "$(dirname "$0")"
FILES=(update.ps1 bulletin-watchdog.ps1 start-bulletin.ps1 suspended.html roku-watch.ps1)

git add "${FILES[@]}"
python3 - "$v" "${FILES[@]}" > manifest.json <<'EOF'
import sys, json, hashlib
v, files = sys.argv[1], sys.argv[2:]
print(json.dumps({"version": v, "files": {f: hashlib.sha256(open(f, "rb").read()).hexdigest().upper() for f in files}}, indent=2))
EOF

key=$(mktemp); trap 'rm -f "$key"' EXIT
security find-generic-password -s kds-kiosk-signing -w | base64 -d > "$key"
openssl dgst -sha256 -sign "$key" manifest.json | base64 | tr -d '\n' > manifest.sig

git add manifest.json manifest.sig
git commit -m "Release v$v" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
git tag "v$v"
git push origin main "v$v"

h=$(shasum -a 256 update.ps1 | cut -d' ' -f1 | tr a-f A-F)
cat <<EOF

Released v$v. Kiosks update within 6 hours.
Bootstrap a NEW kiosk (elevated PowerShell, once):
\$f="\$env:TEMP\update.ps1"; iwr https://raw.githubusercontent.com/KDSystemsInc/vfd-tv-kiosk/v$v/update.ps1 -OutFile \$f -UseBasicParsing; if ((Get-FileHash \$f).Hash -ne '$h') { throw 'hash mismatch' }; powershell -ExecutionPolicy Bypass -File \$f -Install
EOF
