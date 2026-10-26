# Patches against vendored sources

One directory per ham project, named by the project's `name` in the manifest
(not its path, since L4Re nests repos: `mk` is `l4/`, `l4re-core` is
`l4/pkg/l4re-core/`). Patches are `git format-patch` output and apply in
filename order:

    third_party/patches/
      fiasco/0001-....patch
      l4re-core/0001-....patch
      voc/0001-....patch

To generate, from inside the project's checkout under `third_party/sources/`:

    git format-patch -o <repo>/third_party/patches/<project> <upstream-rev>..HEAD
