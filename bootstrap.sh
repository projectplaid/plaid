#!/bin/sh
# Set up the ham workspace in third_party/sources: upstream L4Re manifest plus
# the plaid overlay in third_party/manifests/plaid.xml. Safe to re-run.
set -eu

L4RE_MANIFEST_URL=${L4RE_MANIFEST_URL:-https://github.com/kernkonzept/manifest.git}
L4RE_BRANCH=${L4RE_BRANCH:-master}

cd "$(dirname "$0")/third_party/sources"

if [ ! -d .ham ]; then
  ham init -u "$L4RE_MANIFEST_URL" -b "$L4RE_BRANCH"
fi

mkdir -p .ham/local_manifests
ln -sfn ../../../manifests/plaid.xml .ham/local_manifests/0001-plaid.xml

ham sync "$@"
