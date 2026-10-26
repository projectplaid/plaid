#!/bin/sh
# Set up the ham workspace in third_party/sources: upstream L4Re manifest plus
# the plaid overlay in third_party/manifests/plaid.xml, then apply
# third_party/patches. Safe to re-run.
set -eu

L4RE_MANIFEST_URL=${L4RE_MANIFEST_URL:-https://github.com/kernkonzept/manifest.git}
L4RE_BRANCH=${L4RE_BRANCH:-master}

# Patched projects are checked out on this branch. The ref ham had checked
# out is recorded in branch.<name>.plaidBase, so it can be restored before
# syncing (ham only fast-forwards its own branch).
PATCH_BRANCH=plaid-patched

ROOT=$(cd "$(dirname "$0")" && pwd)
PATCHES_DIR="$ROOT/third_party/patches"

die() { echo "bootstrap: $*" >&2; exit 1; }

# Return a project on the patch branch to its base, refusing to drop work
# that is not in third_party/patches/<name>.
unpatch() {
  name=$1 path=$2
  [ "$(git -C "$path" symbolic-ref -q --short HEAD)" = "$PATCH_BRANCH" ] || return 0

  [ -z "$(git -C "$path" status --porcelain --untracked-files=no)" ] ||
    die "$name has uncommitted changes; commit or stash them first"

  base=$(git -C "$path" config "branch.$PATCH_BRANCH.plaidBase") &&
    git -C "$path" rev-parse -q --verify "$base^{commit}" >/dev/null ||
    die "$name: $PATCH_BRANCH has no valid recorded base"

  known=$(cat "$PATCHES_DIR/$name"/*.patch 2>/dev/null |
          git -C "$path" patch-id --stable | cut -d' ' -f1)
  for id in $(git -C "$path" log -p "$base..HEAD" |
              git -C "$path" patch-id --stable | cut -d' ' -f1); do
    echo "$known" | grep -qx "$id" ||
      die "$name has commits not in third_party/patches/$name;" \
          "export them with git format-patch, or check out $base to discard them"
  done

  git -C "$path" checkout -q "$base"
}

apply_patches() {
  name=$1
  path=$(echo "$projects" | awk -v n="$name" '$1 == n { print $2 }')
  [ -n "$path" ] || die "third_party/patches/$name: no ham project named $name"

  set -- "$PATCHES_DIR/$name"/*.patch
  [ -e "$1" ] || return 0

  base=$(git -C "$path" symbolic-ref -q --short HEAD || git -C "$path" rev-parse HEAD)
  git -C "$path" checkout -q -B "$PATCH_BRANCH"
  git -C "$path" config "branch.$PATCH_BRANCH.plaidBase" "$base"

  if ! git -C "$path" -c advice.mergeConflict=false am -q --3way "$@"; then
    git -C "$path" am --abort
    git -C "$path" checkout -q "$base"
    die "patches for $name no longer apply on $base"
  fi
  echo "patched $name ($# patches on $base)"
}

cd "$ROOT/third_party/sources"

if [ ! -d .ham ]; then
  ham init -u "$L4RE_MANIFEST_URL" -b "$L4RE_BRANCH"
fi

mkdir -p .ham/local_manifests
ln -sfn ../../../manifests/plaid.xml .ham/local_manifests/0001-plaid.xml

projects=$(ham list)
while read -r name path; do
  unpatch "$name" "$path"
done <<EOF
$projects
EOF

ham sync "$@"

projects=$(ham list)
for dir in "$PATCHES_DIR"/*/; do
  [ -d "$dir" ] || continue
  apply_patches "$(basename "$dir")"
done
