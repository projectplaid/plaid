MODULE L4Re;

(* The L4Re environment: the capabilities a program starts with, capability
   slots, and memory as dataspaces. Results are 0 or a negative L4 error. *)

IMPORT SYSTEM, L4;

CONST
  ENOMEM = 12;


PROCEDURE -Aincl1 '#include <l4/re/env.h>';
PROCEDURE -Aincl2 '#include <l4/re/c/dataspace.h>';
PROCEDURE -Aincl3 '#include <l4/re/c/mem_alloc.h>';
PROCEDURE -Aincl4 '#include <l4/re/c/rm.h>';
PROCEDURE -Aincl5 '#include <l4/re/c/util/cap_alloc.h>';
PROCEDURE -Aincl6 '#include <l4/sys/consts.h>';




(* Initial capabilities *)

PROCEDURE -getcap(name: ARRAY OF CHAR): L4.Cap "(ADDRESS)l4re_env_get_cap((char const*)(name))";
PROCEDURE -mainthread(): L4.Cap "(ADDRESS)l4re_env()->main_thread";
PROCEDURE -factory(): L4.Cap "(ADDRESS)l4re_env()->factory";

(* The capability the loader passed under name (ned's caps table), or
   L4.InvalidCap. *)
PROCEDURE GetCap*(name: ARRAY OF CHAR): L4.Cap;
BEGIN RETURN getcap(name) END GetCap;

PROCEDURE MainThread*(): L4.Cap;
BEGIN RETURN mainthread() END MainThread;

PROCEDURE Factory*(): L4.Cap;
BEGIN RETURN factory() END Factory;




(* Capability slots *)

PROCEDURE -capalloc(): L4.Cap "(ADDRESS)l4re_util_cap_alloc()";
PROCEDURE -capfree(cap: L4.Cap) "l4re_util_cap_free((l4_cap_idx_t)(cap))";
PROCEDURE -capfreeunmap(cap: L4.Cap) "l4re_util_cap_free_um((l4_cap_idx_t)(cap))";

(* A free slot, or L4.InvalidCap if there are none. *)
PROCEDURE AllocCap*(): L4.Cap;
BEGIN RETURN capalloc() END AllocCap;

(* Returns an empty slot to the allocator. *)
PROCEDURE FreeCap*(cap: L4.Cap);
BEGIN capfree(cap) END FreeCap;

(* Drops the capability in the slot, then frees the slot. *)
PROCEDURE ReleaseCap*(cap: L4.Cap);
BEGIN capfreeunmap(cap) END ReleaseCap;




(* Dataspaces *)

PROCEDURE -allocds(size: SYSTEM.ADDRESS; ds: L4.Cap): LONGINT
"(INT32)l4re_ma_alloc((long)(size), (l4re_ds_t)(ds), 0)";
PROCEDURE -dssize(ds: L4.Cap): SYSTEM.ADDRESS "(ADDRESS)l4re_ds_size((l4re_ds_t)(ds))";
PROCEDURE -roundpage(size: SYSTEM.ADDRESS): SYSTEM.ADDRESS "(ADDRESS)l4_round_page((l4_addr_t)(size))";
PROCEDURE -attach(VAR address: SYSTEM.ADDRESS; size: SYSTEM.ADDRESS; ds: L4.Cap): LONGINT
"(INT32)l4re_rm_attach((void**)(address), (unsigned long)(size), L4RE_RM_F_SEARCH_ADDR | L4RE_RM_F_RW, (l4re_ds_t)(ds), 0, L4_PAGESHIFT)";
PROCEDURE -detach(address: SYSTEM.ADDRESS; VAR ds: L4.Cap): LONGINT
"(INT32)l4re_rm_detach_ds((void*)(address), (l4re_ds_t*)(ds))";

(* Allocates a dataspace of at least size bytes into a new slot ds. *)
PROCEDURE AllocDataspace*(size: SYSTEM.ADDRESS; VAR ds: L4.Cap): LONGINT;
  VAR e: LONGINT;
BEGIN
  ds := capalloc();
  IF ~L4.IsValid(ds) THEN RETURN -ENOMEM END;
  e := allocds(roundpage(size), ds);
  IF e < 0 THEN capfree(ds); ds := L4.InvalidCap END;
  RETURN e
END AllocDataspace;

(* The dataspace's size in bytes, or a negative L4 error. *)
PROCEDURE DataspaceSize*(ds: L4.Cap): SYSTEM.ADDRESS;
BEGIN RETURN dssize(ds) END DataspaceSize;

(* Makes the first size bytes of ds readable and writable at a free address,
   returned in address. *)
PROCEDURE Attach*(ds: L4.Cap; size: SYSTEM.ADDRESS; VAR address: SYSTEM.ADDRESS): LONGINT;
BEGIN
  address := 0;
  RETURN attach(address, roundpage(size), ds)
END Attach;

(* Removes the region at address; ds is the dataspace that backed it, still
   held by the caller. *)
PROCEDURE Detach*(address: SYSTEM.ADDRESS; VAR ds: L4.Cap): LONGINT;
  VAR e: LONGINT;
BEGIN
  e := detach(address, ds);
  IF e > 0 THEN e := 0 END;  (* Positive results only describe the detach. *)
  RETURN e
END Detach;

END L4Re.
