# Porting voc to L4Re/Fiasco

Settled design decisions for running Vishap Oberon (voc) programs on
L4Re. Change them here when they change, so they stay the reference.

## Build model

- voc is a cross compiler. The compiler itself is built and runs on the
  Linux host with `PLATFORM=unix`; only the runtime and library modules
  are translated for L4Re. There is no `bootstrap/l4re-*`.
- voc emits C on the host (`voc -S`), and BID compiles that C for L4Re.
  `pkg/voc-runtime` translates voc's runtime library once into
  `libvoc-runtime.a` and installs its headers and symbol files under
  `$(OBJ_BASE)/lib/<system>/voc`. Programs include `mk/voc-prog.mk`,
  name their modules (`VOC_MAIN`, `VOC_MODULES`) and are translated
  against those symbol files (see `apps/hello`). `VOC_PLATFORM` (`l4re`
  by default, or `unix`) selects the Platform variant; a program refuses
  to build against a runtime built for the other one. The top-level
  `make` builds the packages in dependency order.
- Oberon libraries include `mk/voc-lib.mk` (`VOC_LIB`, `VOC_MODULES`)
  and install into the same export dir; packages that import them name
  them in `VOC_LIBS`. Translation runs with `OBERON=".;<export dir>"`, so
  a package's own symbol files win over installed ones, and with `-F` so
  voc always writes them.
- In code procedures (`PROCEDURE -name(...) "C"`) wrap every parameter
  in parentheses: voc emits them as C macros without parenthesizing the
  arguments, so `(size_t)n * 8` called with `a + b` computes `a + b*8`.
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

## Kernel interface

`pkg/oberon-l4` lets Oberon programs use L4Re directly, so services can
be written in Oberon. Module `L4` wraps the kernel (capabilities, IPC,
IPC gates); `L4Re` wraps the environment (named capabilities, capability
slots, dataspaces). A server module (registry, dispatch loop, sessions)
comes next. `apps/l4-echo` is the reference test: an echo server and
client connected by ned, passing strings and a dataspace capability.

- An `L4.Message` holds what goes into or out of the message registers.
  Every IPC procedure loads the UTCB from it and copies the result back
  in one step: anything else that does IPC (`Out`, or `NEW` growing the
  heap) reuses the same registers, so callers never touch the UTCB.
- Capability indexes and words are `SYSTEM.ADDRESS`: under `-O2`,
  `LONGINT` is only 32 bits.
- `Call` returns a negative IPC error or the reply's label (0 or a
  negative error); `L4.IsIpcError` tells the two apart.
- A gate's label must keep its low two bits zero; the kernel ORs the
  sender's rights into them. When the label is an object's address, the
  server must also keep a reference to the object: the kernel's copy is
  invisible to the GC. voc's heap never moves objects.
- Servers are single-threaded: voc's runtime and GC are not thread-safe.
- Platform does not import these modules; it must start before Heap and
  stays self-contained.

## Files and the VFS

Plaid's userspace does not use musl's POSIX file API. Files go through
Plaid's own VFS, an IPC protocol over L4Re capabilities. The VFS server
is written in Oberon, on `pkg/oberon-l4`.

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

### Protocol (planned)

The protocol's constants are shared by the server and Platforml4re, the
client. With the server in Oberon they belong in an Oberon module rather
than a C header. Platform cannot import `oberon-l4`, which is built after
the runtime, so how Platforml4re does its IPC (its own few calls, or `L4`
moved into the runtime ahead of Platform) is still open.

- msgtag label = protocol ID (around `0x5000`, clear of the kernel's
  values at or below 0 and L4Re's `0x4000` range); MR0 = opcode.
- reply label = 0 or a negative error, so `l4_error()` works.
- its own `PLAID_VFS_E*` values with Linux numbers. `L4_E*` is not
  reused: it lacks codes Platform needs and `L4_EBADPROTO` (39) collides
  with `ENOTEMPTY`.

## Status

- `apps/hello` (Oberon-2 hello world) builds and runs on L4Re with
  `VOC_PLATFORM=unix`; the Unix runtime links against L4Re's musl as is.
- `Platforml4re.Mod` runs hello with `VOC_PLATFORM=l4re`: console output
  goes to the L4Re log capability, `Time` reads the KIP clock and `Delay`
  sleeps with an IPC timeout. `OSAllocate` gives each heap chunk its own
  dataspace from the L4Re memory allocator, attached anywhere and rounded
  up to pages; `OSFree` detaches it and drops the capability, which frees
  the memory. Only `getenv` and `exit` still come from musl. Lookups
  (open, stat, unlink, rename, chdir) fail with `ENOENT`,
  creation with `ENOSYS`, terminal control with `ENOTTY`; there is no
  wall clock yet. `PlatformNativel4re.Mod` is empty.
- `SYSTEM.c`/`SYSTEM.h` have a `VOC_L4RE` branch: no signal handling,
  and command recovery reduces to running the command (generated code
  still calls `SYSTEM_CommandCritical`/`SYSTEM_CheckCommandInterrupt`, so
  they remain as no-ops). `apps/hello` defaults to `VOC_PLATFORM=l4re`
  and defines `VOC_L4RE` exactly when that platform is selected.
