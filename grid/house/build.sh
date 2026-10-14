#!/bin/sh
set -eu

if [ "$#" -ne 2 ]; then
    echo 'usage: build.sh {server|client|test_house|inspect} output.c' >&2
    exit 2
fi
case "$1" in
    server|client|test_house|inspect) ;;
    *) echo 'unknown house program' >&2; exit 2 ;;
esac

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT HUP INT TERM
mkdir "$stage/stdlib"
cp "$project_root"/stdlib/*.o9 "$stage/stdlib/"
cp "$project_root"/stdlib/*.o9 "$stage/"
cp "$project_root"/grid/house/*.o9 "$stage/"
"$project_root/o9c/o9c" "$stage/$1.o9" >"$2"
