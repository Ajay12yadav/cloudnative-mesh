#!/usr/bin/env bash
# Writes YOUR GitHub repo URL (from "git remote origin") into the gitops/ files.
# Idempotent: safe to run again.  Usage: bash scripts/set-repo-url.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

URL="$(git remote get-url origin)"
# convert git@github.com:user/repo.git  ->  https://github.com/user/repo.git
URL="$(echo "$URL" | sed -E 's#^git@github.com:#https://github.com/#')"
case "$URL" in *.git) ;; *) URL="$URL.git" ;; esac

sed -i -E "s#(repoURL: )https://github.com/[^[:space:]]+#\1$URL#" \
  gitops/bootstrap/root-app.yaml gitops/apps/*.yaml
echo "repoURL set to: $URL"
