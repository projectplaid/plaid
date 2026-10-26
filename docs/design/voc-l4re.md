# Porting voc to L4Re/Fiasco

Settled design decisions for running Vishap Oberon (voc) programs on
L4Re. Change them here when they change, so they stay the reference.

## Build model

- voc is a cross compiler. The compiler itself is built and runs on the
  Linux host with `PLATFORM=unix`; only the runtime and library modules
  are translated for L4Re. There is no `bootstrap/l4re-*`.
- voc emits C on the host (`voc -S`), and BID compiles that C for L4Re.
  `apps/hello` is the reference package: its Makefile translates the
  runtime into the object dir and selects the Platform variant with
  `VOC_PLATFORM` (`unix` or `l4re`).
- The in-tree voc build (`$VOC_ROOT/install`, see `.envrc`) is the one
  to use. Its install dir is baked into the compiler, so it never reads
  symbol files from an older system-wide voc.
- voc changes live on the `plaid-patched` branch of
  `third_party/sources/voc` and are exported to `third_party/patches/voc`
  (see `third_party/patches/README.md`).

## Platform variant

- L4Re gets its own `src/runtime/Platforml4re.Mod` and
  `PlatformNativel4re.Mod` from the start, rather than reusing
  `Platformunix` with conditionals. The module is still named `Platform`
  and keeps Platformunix's full export list, stubs included, so library
  modules compile unchanged.
- `Heap` calls `Platform_OSAllocate` by its C name, and may do so before
  Platform's module body runs. `OSAllocate` must not depend on state set
  up in that body.
- The C guard for L4Re code in shared runtime C (`SYSTEM.c`/`SYSTEM.h`)
  is `VOC_L4RE`, set from the BID Makefile. L4Re's compilers still
  define `__linux__`/`__unix__`, and BID's only L4Re marker is
  `L4API_l4f`, so neither is used directly.
- Error codes keep Platformunix's `ErrorCode` names and Linux values, as
  literals rather than `errno.h` macros.

## Files and the VFS

Plaid's userspace does not use musl's POSIX file API. Files go through
Plaid's own VFS, an IPC protocol over L4Re capabilities.

- `FileHandle` stays `LONGINT`. `StdIn`/`StdOut`/`StdErr` stay the
  constants 0/1/2 and map to the log/vcon capability, not the VFS; file
  handles start at 3 and index a client-side handle table.
- Each open file has one shared dataspace for bulk data; IPC carries only
  control. Transfers larger than the dataspace loop inside Platform.
- The file position lives in the client handle table. `read`/`write`
  carry an explicit offset, so the server keeps no per-transfer state;
  `Seek`/`Tell` involve no IPC.
- The working directory (`chdir`/`getcwd`, `Platform.CWD`) is client-side
  state. Paths are made absolute before they are sent.
- Paths travel inline in IPC messages. `PLAID_VFS_PATH_MAX` is 240: two
  paths for `rename` exactly fill the 63 message registers.

### Sessions

Each client's `vfs` capability is its own session gate, created through
the `L4::Factory` protocol (ned's `:create()`), as moe does it:

- the server drops its own reference to each session gate
  (`dec_refcnt(1)`) so only the client keeps it alive;
- it registers a deletion IRQ on its thread and, when it fires, checks
  every session with `validate()` and tears down dead ones (closing files
  and unmapping dataspaces).

See `l4/pkg/l4re-core/moe/server/src/alloc.cc` (`register_ipc_object`)
and `obj_reg.h` (`handle_irq`). File and directory ids are scoped to a
session; an unknown id is `EBADF`.

### Protocol header (planned)

`pkg/plaid-vfs/include/vfs_proto.h`, shared by the C client shim, the
C++ server and Platforml4re:

- msgtag label = protocol ID (around `0x5000`, clear of the kernel's
  values at or below 0 and L4Re's `0x4000` range); MR0 = opcode.
- reply label = 0 or a negative error, so `l4_error()` works.
- its own `PLAID_VFS_E*` values with Linux numbers. `L4_E*` is not
  reused: it lacks codes Platform needs and `L4_EBADPROTO` (39) collides
  with `ENOTEMPTY`.

## Status

- `apps/hello` (Oberon-2 hello world) builds and runs on L4Re with
  `VOC_PLATFORM=unix`; the Unix runtime links against L4Re's musl as is.
- `Platforml4re.Mod` and `PlatformNativel4re.Mod` are, for now, copies
  of the Unix versions. Next milestone: hello running with
  `VOC_PLATFORM=l4re` and console output going straight to the log
  capability.
