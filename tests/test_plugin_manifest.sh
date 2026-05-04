#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
[ -f .claude-plugin/plugin.json ] || { echo "FAIL: manifest missing"; exit 1; }
python3 -c "import json,sys; d=json.load(open('.claude-plugin/plugin.json')); assert d['name']=='super-manus', d; assert 'version' in d; assert 'description' in d"
echo OK
