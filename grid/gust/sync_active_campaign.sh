#!/usr/bin/env bash
set -euo pipefail

# The 9front grid sees this workstation's tree through drawterm's 9P export.
# Gust runs on a different Linux host, so mirror only the read-only inputs it
# needs. No queue or worker state is copied back to the active campaign.
campaign=/tmp/o9mut-campaign-20261003-full
manifest=/home/scott/Repo/objective-9c/o9c/test/artifacts/o9um_grid_manifest_20261003_900s.tsv
remote=rentonsoftworks-lan
destination=/home/scott/services/gust/campaigns/active

test -f "$manifest"
test -d "$campaign/results"
test -d "$campaign/logs"

ssh -o BatchMode=yes -o ConnectTimeout=10 "$remote" \
  "mkdir -p '$destination/results' '$destination/logs' '$destination/queue' '$destination/workers'"

sync_dir() {
  local source=$1 target=$2 rc
  if rsync -azq --timeout=120 "$source/" "$remote:$destination/$target/"; then
    return 0
  else
    rc=$?
    # A live worker may remove a log after rsync has listed it.
    if [[ $rc -ne 24 ]]; then
      return "$rc"
    fi
  fi
}

rsync -azq --timeout=120 "$manifest" "$remote:$destination/manifest.tsv"
sync_dir "$campaign/results" results
sync_dir "$campaign/logs" logs
sync_dir "$campaign/workers" workers
rsync -azq --timeout=120 "$campaign/queue/counts.tab" "$remote:$destination/queue/counts.tab"
ssh -o BatchMode=yes -o ConnectTimeout=10 "$remote" "touch '$destination/sync-complete'"

echo "Gust mirror updated: $destination"
