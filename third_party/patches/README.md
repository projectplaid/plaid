# Patches against vendored sources

One directory per ham project, named by the project's `name` in the manifest
(not its path, since L4Re nests repos: `mk` is `l4/`, `l4re-core` is
`l4/pkg/l4re-core/`). Patches are `git format-patch` output and apply in
filename order:

    third_party/patches/
      fiasco/0001-....patch
      l4re-core/0001-....patch
      voc/0001-....patch

`bootstrap.sh` applies them with `git am` onto a local `plaid-patched` branch
in each project, after `ham sync`. Before syncing it switches that project
back to the ref ham manages, and stops instead if the branch has
uncommitted changes or commits not exported here.

To change a project's patches, commit on `plaid-patched` and re-export:

    cd third_party/sources/<path>
    rm -f <repo>/third_party/patches/<project>/*.patch
    git format-patch -o <repo>/third_party/patches/<project> \
        "$(git config branch.plaid-patched.plaidBase)"..HEAD
