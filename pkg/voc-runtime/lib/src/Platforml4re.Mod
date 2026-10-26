MODULE Platform;
IMPORT SYSTEM;

(* L4Re/Fiasco variant. Keeps Platformunix's interface. The console goes to
   the L4Re log capability and time comes from the kernel; files, directories
   and terminals need Plaid's VFS and fail until it exists. *)

CONST
  StdIn-  = 0;
  StdOut- = 1;
  StdErr- = 2;

  ReadOnly* = 0;
  WriteOnly* = 1;
  ReadWrite* = 2;
  OpenExisting* = 0;
  CreateAlways* = 1;
  OpenAlways* = 2;

  (* Linux errno values, so ErrorCodes mean the same as under Platformunix. *)
  ENOENT       = 2;
  EINTR        = 4;
  EIO          = 5;
  EBADF        = 9;
  EAGAIN       = 11;
  EACCES       = 13;
  EXDEV        = 18;
  EINVAL       = 22;
  ENFILE       = 23;
  EMFILE       = 24;
  ENOTTY       = 25;
  ESPIPE       = 29;
  EROFS        = 30;
  ENOSYS       = 38;
  ENETUNREACH  = 101;
  ECONNABORTED = 103;
  ETIMEDOUT    = 110;
  ECONNREFUSED = 111;
  EHOSTUNREACH = 113;

  NameMax = 255;
  PathMax = 240;   (* PLAID_VFS_PATH_MAX: two paths fill one IPC message. *)

  LogChunk = 4096; (* Bytes handed to the log capability per call. *)

TYPE
  SignalHandler = PROCEDURE(signal: SYSTEM.INT32);
  Command* = PROCEDURE;

  ErrorCode*  = INTEGER;
  FileHandle* = LONGINT;
  TerminalState* = SYSTEM.ADDRESS;
  DirectoryHandle* = SYSTEM.ADDRESS;

  FileIdentity* = RECORD
    volume: LONGINT;
    index:  LONGINT;
    mtime:  LONGINT;  (* Seconds since the epoch, UTC. *)
  END;

VAR
  LittleEndian-:   BOOLEAN;
  PID-:            INTEGER;
  CWD-:            ARRAY 256 OF CHAR;  (* Client-side; the VFS sees absolute paths. *)
  TimeStart:       SYSTEM.INT64;
  lastError:       ErrorCode;

  SeekSet-:        INTEGER;
  SeekCur-:        INTEGER;
  SeekEnd-:        INTEGER;

  NL-:             ARRAY 3 OF CHAR;  (* Platform specific newline representation *)



(* L4Re headers to be included *)

PROCEDURE -Aincl1 '#include <stdlib.h>';  (* getenv, exit *)
PROCEDURE -Aincl2 '#include <l4/re/env.h>';
PROCEDURE -Aincl3 '#include <l4/re/c/log.h>';
PROCEDURE -Aincl4 '#include <l4/re/c/mem_alloc.h>';
PROCEDURE -Aincl5 '#include <l4/re/c/rm.h>';
PROCEDURE -Aincl6 '#include <l4/re/c/util/cap_alloc.h>';
PROCEDURE -Aincl7 '#include <l4/sys/consts.h>';
PROCEDURE -Aincl8 '#include <l4/sys/ipc.h>';
PROCEDURE -Aincl9 '#include <l4/sys/kip.h>';




(* Error codes *)

PROCEDURE Fail(e: ErrorCode): ErrorCode;
BEGIN lastError := e; RETURN e END Fail;

PROCEDURE Error*(): ErrorCode; BEGIN RETURN lastError END Error;

PROCEDURE TooManyFiles*(e: ErrorCode): BOOLEAN;
BEGIN RETURN (e = EMFILE) OR (e = ENFILE) END TooManyFiles;

PROCEDURE NoSuchDirectory*(e: ErrorCode): BOOLEAN;
BEGIN RETURN e = ENOENT END NoSuchDirectory;

PROCEDURE DifferentFilesystems*(e: ErrorCode): BOOLEAN;
BEGIN RETURN e = EXDEV END DifferentFilesystems;

PROCEDURE Inaccessible*(e: ErrorCode): BOOLEAN;
BEGIN RETURN (e = EACCES) OR (e = EROFS) OR (e = EAGAIN) END Inaccessible;

PROCEDURE Absent*(e: ErrorCode): BOOLEAN;
BEGIN RETURN e = ENOENT END Absent;

PROCEDURE TimedOut*(e: ErrorCode): BOOLEAN;
BEGIN RETURN e = ETIMEDOUT END TimedOut;

PROCEDURE ConnectionFailed*(e: ErrorCode): BOOLEAN;
BEGIN RETURN (e = ECONNREFUSED) OR (e = ECONNABORTED)
          OR (e = ENETUNREACH)  OR (e = EHOSTUNREACH) END ConnectionFailed;

PROCEDURE Interrupted*(e: ErrorCode): BOOLEAN;
BEGIN RETURN e = EINTR END Interrupted;




(* Expose file and path name length limits *)

PROCEDURE MaxNameLength*(): INTEGER;  BEGIN RETURN NameMax END MaxNameLength;
PROCEDURE MaxPathLength*(): INTEGER;  BEGIN RETURN PathMax END MaxPathLength;




(* OS memory allocaton. Each block is its own dataspace from the L4Re memory
   allocator, attached anywhere in the address space; detaching it gives the
   dataspace back, so no bookkeeping is needed here. Heap calls
   Platform_OSAllocate by its C name before any module body has run, so this
   must not depend on this module's body. *)

PROCEDURE -capalloc(): SYSTEM.ADDRESS "(ADDRESS)l4re_util_cap_alloc()";
PROCEDURE -capvalid(cap: SYSTEM.ADDRESS): BOOLEAN "!l4_is_invalid_cap((l4_cap_idx_t)cap)";
PROCEDURE -capfree(cap: SYSTEM.ADDRESS) "l4re_util_cap_free((l4_cap_idx_t)cap)";
PROCEDURE -capfreeunmap(cap: SYSTEM.ADDRESS) "l4re_util_cap_free_um((l4_cap_idx_t)cap)";
PROCEDURE -roundpage(size: SYSTEM.ADDRESS): SYSTEM.ADDRESS "(ADDRESS)l4_round_page((l4_addr_t)size)";

PROCEDURE -allocds(size, ds: SYSTEM.ADDRESS): SYSTEM.INT32
"l4re_ma_alloc((long)size, (l4re_ds_t)ds, 0)";

PROCEDURE -attach(VAR address: SYSTEM.ADDRESS; size, ds: SYSTEM.ADDRESS): SYSTEM.INT32
"l4re_rm_attach((void**)address, (unsigned long)size, L4RE_RM_F_SEARCH_ADDR | L4RE_RM_F_RW, (l4re_ds_t)ds, 0, L4_PAGESHIFT)";

PROCEDURE -detach(address: SYSTEM.ADDRESS; VAR ds: SYSTEM.ADDRESS): SYSTEM.INT32
"l4re_rm_detach_ds((void*)address, (l4re_ds_t*)ds)";

PROCEDURE OSAllocate*(size: SYSTEM.ADDRESS): SYSTEM.ADDRESS;
  VAR ds, address: SYSTEM.ADDRESS;
BEGIN
  ds := capalloc();
  IF ~capvalid(ds) THEN RETURN 0 END;
  size := roundpage(size);
  IF allocds(size, ds) < 0 THEN capfree(ds); RETURN 0 END;
  address := 0;
  IF attach(address, size, ds) < 0 THEN capfreeunmap(ds); RETURN 0 END;
  RETURN address
END OSAllocate;

PROCEDURE OSFree*(address: SYSTEM.ADDRESS);
  VAR ds: SYSTEM.ADDRESS;
BEGIN
  IF (address # 0) & (detach(address, ds) >= 0) THEN capfreeunmap(ds) END
END OSFree;




(* Program environment, as passed by the L4Re loader *)

PROCEDURE -getenv(var: ARRAY OF CHAR): SYSTEM.ADDRESS "getenv((char*)var)";

PROCEDURE getEnv*(var: ARRAY OF CHAR; VAR val: ARRAY OF CHAR): BOOLEAN;
TYPE EnvPtr = POINTER TO ARRAY 1024 OF CHAR;
VAR  p: EnvPtr;
BEGIN
  p := SYSTEM.VAL(EnvPtr, getenv(var));
  IF p # NIL THEN COPY(p^, val) END;
  RETURN p # NIL;
END getEnv;

PROCEDURE GetEnv*(var: ARRAY OF CHAR; VAR val: ARRAY OF CHAR);
BEGIN
  IF ~getEnv(var, val) THEN val[0] := 0X END;
END GetEnv;




(* Signals and traps: L4Re has none to hook, and no command cancellation. *)

PROCEDURE SetInterruptHandler*(handler: SignalHandler);
BEGIN END SetInterruptHandler;

PROCEDURE SetQuitHandler*(handler: SignalHandler);
BEGIN END SetQuitHandler;

PROCEDURE SetBadInstructionHandler*(handler: SignalHandler);
BEGIN END SetBadInstructionHandler;

(* 0 after the command returns, or a negative error if it cannot be run. *)
PROCEDURE RunCommand*(command: Command): SYSTEM.INT32;
BEGIN
  IF command = NIL THEN RETURN -EINVAL END;
  command; RETURN 0
END RunCommand;

PROCEDURE CommandCritical*(enter: BOOLEAN);
BEGIN END CommandCritical;




(* Time. The KIP clock counts microseconds since boot; there is no wall
   clock yet, so the time of day reads as unavailable (zero). *)

PROCEDURE -kipclock(): SYSTEM.INT64 "(INT64)l4_kip_clock(l4re_kip())";

PROCEDURE GetClock*(VAR t, d: LONGINT);
BEGIN t := 0; d := 0
END GetClock;

PROCEDURE GetTimeOfDay*(VAR sec, usec: LONGINT);
BEGIN sec := 0; usec := 0
END GetTimeOfDay;

PROCEDURE Time*(): LONGINT;
BEGIN RETURN SHORT((kipclock() DIV 1000 - TimeStart) MOD 7FFFFFFFH)
END Time;


PROCEDURE -sleepms(ms: LONGINT) "l4_ipc_sleep_ms((l4_uint32_t)ms)";

PROCEDURE Delay*(ms: LONGINT);
BEGIN IF ms > 0 THEN sleepms(ms) END
END Delay;




(* System call *)

PROCEDURE System*(cmd : ARRAY OF CHAR): INTEGER;
BEGIN lastError := ENOSYS; RETURN -1
END System;




(* Console: handles 0-2. Output goes to the L4Re log; there is no input yet. *)

PROCEDURE IsConsole*(h: FileHandle): BOOLEAN;
BEGIN RETURN (h >= StdIn) & (h <= StdErr) END IsConsole;

(* Handle-based operations that only real files support. *)
PROCEDURE NotFile(h: FileHandle): ErrorCode;
BEGIN
  IF IsConsole(h) THEN RETURN Fail(ESPIPE) ELSE RETURN Fail(EBADF) END
END NotFile;




(* File system: no VFS yet, so nothing exists and nothing can be created. *)

PROCEDURE OpenDirectory*(path: ARRAY OF CHAR;
                        VAR handle: DirectoryHandle): ErrorCode;
BEGIN handle := 0; RETURN Fail(ENOENT)
END OpenDirectory;

(* done distinguishes end-of-directory from errors. *)
PROCEDURE ReadDirectory*(handle: DirectoryHandle; VAR name: ARRAY OF CHAR;
                        VAR done: BOOLEAN): ErrorCode;
BEGIN
  IF LEN(name) > 0 THEN name[0] := 0X END;
  done := TRUE; RETURN Fail(EBADF)
END ReadDirectory;

PROCEDURE CloseDirectory*(VAR handle: DirectoryHandle): ErrorCode;
BEGIN
  IF handle = 0 THEN RETURN 0 END;
  handle := 0; RETURN Fail(EBADF)
END CloseDirectory;

PROCEDURE IsDirectory*(path: ARRAY OF CHAR): BOOLEAN;
BEGIN RETURN FALSE
END IsDirectory;


(* File APIs *)

PROCEDURE OldRO*(VAR n: ARRAY OF CHAR; VAR h: FileHandle): ErrorCode;
BEGIN RETURN Fail(ENOENT)
END OldRO;

PROCEDURE OldRW*(VAR n: ARRAY OF CHAR; VAR h: FileHandle): ErrorCode;
BEGIN RETURN Fail(ENOENT)
END OldRW;

PROCEDURE New*(VAR n: ARRAY OF CHAR; VAR h: FileHandle): ErrorCode;
BEGIN RETURN Fail(ENOSYS)
END New;

PROCEDURE OpenFile*(VAR n: ARRAY OF CHAR; access, creation: INTEGER;
                    VAR h: FileHandle): ErrorCode;
BEGIN
  IF creation = OpenExisting THEN RETURN Fail(ENOENT) ELSE RETURN Fail(ENOSYS) END
END OpenFile;

PROCEDURE Close*(h: FileHandle): ErrorCode;
BEGIN
  IF IsConsole(h) THEN RETURN 0 ELSE RETURN Fail(EBADF) END
END Close;

PROCEDURE SetFileMTime* (VAR n: ARRAY OF CHAR; year, month, day,
                         hour, minute, second: LONGINT): ErrorCode;
BEGIN RETURN Fail(ENOENT)
END SetFileMTime;




(* Terminal control needs a vcon-backed console. *)

PROCEDURE CaptureTerminalState*(h: FileHandle;
                                VAR state: TerminalState): ErrorCode;
BEGIN state := 0; RETURN Fail(ENOTTY)
END CaptureTerminalState;

PROCEDURE RestoreTerminalState*(h: FileHandle;
                                state: TerminalState): ErrorCode;
BEGIN ASSERT(state # 0); RETURN Fail(ENOTTY)
END RestoreTerminalState;

PROCEDURE ReleaseTerminalState*(VAR state: TerminalState);
BEGIN state := 0
END ReleaseTerminalState;

PROCEDURE CopyTerminalState*(source: TerminalState; VAR copy: TerminalState): ErrorCode;
BEGIN ASSERT(source # 0); copy := 0; RETURN Fail(ENOTTY)
END CopyTerminalState;

PROCEDURE MakeTerminalRaw*(state: TerminalState);
BEGIN ASSERT(state # 0)
END MakeTerminalRaw;

PROCEDURE SetTerminalTimeout*(state: TerminalState; tenths: INTEGER);
BEGIN ASSERT((state # 0) & (tenths >= 0) & (tenths <= 255))
END SetTerminalTimeout;

PROCEDURE SetTerminalEcho*(h: FileHandle; enabled: BOOLEAN): ErrorCode;
BEGIN RETURN Fail(ENOTTY)
END SetTerminalEcho;

PROCEDURE SetTerminalInputMode*(h: FileHandle; raw: BOOLEAN): ErrorCode;
BEGIN RETURN Fail(ENOTTY)
END SetTerminalInputMode;

PROCEDURE SetTerminalOutputMode*(h: FileHandle; raw: BOOLEAN): ErrorCode;
BEGIN RETURN Fail(ENOTTY)
END SetTerminalOutputMode;

PROCEDURE GetTerminalSize*(h: FileHandle;
                           VAR lines, columns: INTEGER): ErrorCode;
BEGIN RETURN Fail(ENOTTY)
END GetTerminalSize;

PROCEDURE GetTerminalDimensions*(h: FileHandle; VAR lines, columns: LONGINT): ErrorCode;
BEGIN RETURN Fail(ENOTTY)
END GetTerminalDimensions;

PROCEDURE SameTerminal*(first, second: FileHandle): BOOLEAN;
BEGIN RETURN IsConsole(first) & IsConsole(second)
END SameTerminal;




(* File identity *)

PROCEDURE Identify*(h: FileHandle; VAR identity: FileIdentity): ErrorCode;
BEGIN RETURN NotFile(h)
END Identify;

PROCEDURE IdentifyByName*(n: ARRAY OF CHAR; VAR identity: FileIdentity): ErrorCode;
BEGIN RETURN Fail(ENOENT)
END IdentifyByName;


PROCEDURE SameFile*(i1, i2: FileIdentity): BOOLEAN;
BEGIN RETURN (i1.index = i2.index) & (i1.volume = i2.volume)
END SameFile;

PROCEDURE SameFileTime*(i1, i2: FileIdentity): BOOLEAN;
BEGIN RETURN i1.mtime = i2.mtime
END SameFileTime;

PROCEDURE SetMTime*(VAR target: FileIdentity; source: FileIdentity);
BEGIN target.mtime := source.mtime;
END SetMTime;

(* No wall-clock conversion yet; reads as unavailable, like GetClock. *)
PROCEDURE MTimeAsClock*(i: FileIdentity; VAR t, d: LONGINT);
BEGIN t := 0; d := 0
END MTimeAsClock;


PROCEDURE Size*(h: FileHandle; VAR l: LONGINT): ErrorCode;
BEGIN RETURN NotFile(h)
END Size;




(* Read and write *)

PROCEDURE Read*(h: FileHandle; p: SYSTEM.ADDRESS; l: LONGINT; VAR n: LONGINT): ErrorCode;
BEGIN
  n := 0;
  IF l < 0 THEN RETURN Fail(EINVAL) END;
  IF h = StdIn THEN RETURN 0 END;  (* End of input. *)
  RETURN Fail(EBADF)
END Read;

PROCEDURE ReadBuf*(h: FileHandle; VAR b: ARRAY OF SYSTEM.BYTE; VAR n: LONGINT): ErrorCode;
BEGIN RETURN Read(h, SYSTEM.ADR(b), LEN(b), n)
END ReadBuf;


PROCEDURE -logprintn(p: SYSTEM.ADDRESS; l: LONGINT)
"l4re_log_printn((char const*)(ADDRESS)p, (int)l)";

PROCEDURE WriteCount*(h: FileHandle; p: SYSTEM.ADDRESS; l: LONGINT;
                      VAR n: LONGINT): ErrorCode;
BEGIN
  n := 0;
  IF l < 0 THEN RETURN Fail(EINVAL) END;
  IF (h # StdOut) & (h # StdErr) THEN RETURN Fail(EBADF) END;
  IF l > LogChunk THEN n := LogChunk ELSE n := l END;
  IF n > 0 THEN logprintn(p, n) END;
  RETURN 0
END WriteCount;

PROCEDURE Write*(h: FileHandle; p: SYSTEM.ADDRESS; l: LONGINT): ErrorCode;
  (* WriteCount remains a single attempt. Write must not report success until
     the complete buffer has been written. *)
  VAR written: LONGINT; e: ErrorCode;
BEGIN
  IF l < 0 THEN RETURN Fail(EINVAL) END;
  WHILE l > 0 DO
    e := WriteCount(h, p, l, written);
    IF e # 0 THEN RETURN e END;
    INC(p, written); DEC(l, written)
  END;
  RETURN 0
END Write;




PROCEDURE Sync*(h: FileHandle): ErrorCode;
BEGIN
  IF IsConsole(h) THEN RETURN 0 ELSE RETURN Fail(EBADF) END
END Sync;

PROCEDURE Seek*(h: FileHandle; offset: LONGINT; whence: INTEGER): ErrorCode;
BEGIN RETURN NotFile(h)
END Seek;

PROCEDURE Tell*(h: FileHandle; VAR offset: LONGINT): ErrorCode;
BEGIN offset := 0; RETURN NotFile(h)
END Tell;

PROCEDURE Truncate*(h: FileHandle; l: LONGINT): ErrorCode;
BEGIN RETURN NotFile(h)
END Truncate;

PROCEDURE Unlink*(VAR n: ARRAY OF CHAR): ErrorCode;
BEGIN RETURN Fail(ENOENT)
END Unlink;

(* Will check the directory through the VFS, then update CWD. *)
PROCEDURE Chdir*(VAR n: ARRAY OF CHAR): ErrorCode;
BEGIN RETURN Fail(ENOENT)
END Chdir;

PROCEDURE Rename*(VAR o,n: ARRAY OF CHAR): ErrorCode;
BEGIN RETURN Fail(ENOENT)
END Rename;




(* Process termination *)

PROCEDURE -exit(code: LONGINT) "exit((int)code)";
PROCEDURE Exit*(code: LONGINT); BEGIN exit(code) END Exit;



PROCEDURE TestLittleEndian;
  VAR i: INTEGER;
 BEGIN i := 1; SYSTEM.GET(SYSTEM.ADR(i), LittleEndian); END TestLittleEndian;


BEGIN
  TestLittleEndian;

  TimeStart := kipclock() DIV 1000;
  lastError := 0;
  PID       := 1;
  CWD       := "/";

  SeekSet := 0;
  SeekCur := 1;
  SeekEnd := 2;

  NL[0] := 0AX; (* LF *)
  NL[1] := 0X;
END Platform.
