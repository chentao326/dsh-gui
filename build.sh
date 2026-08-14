#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

SDK=""
for cand in MacOSX15.2.sdk MacOSX15.sdk MacOSX14.5.sdk MacOSX.sdk; do
  if [ -d "/Library/Developer/CommandLineTools/SDKs/$cand" ]; then SDK="/Library/Developer/CommandLineTools/SDKs/$cand"; break; fi
done
[ -n "$SDK" ] || { echo "ERROR: no SDK found under /Library/Developer/CommandLineTools/SDKs"; exit 1; }
mkdir -p build/modcache
echo "SDK: $SDK"
