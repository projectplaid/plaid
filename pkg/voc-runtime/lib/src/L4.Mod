MODULE L4;

(* The Fiasco kernel interface: capabilities, IPC and IPC gates.

   A Message holds what goes into or comes out of the UTCB's message
   registers. Every IPC procedure here loads the UTCB from a Message and
   copies the result back in one step, because anything else that does IPC
   (Out, or NEW growing the heap) reuses the same registers. So build a
   Message, call, then read the Message; never expect the UTCB to keep
   anything between calls.

   Capability indexes and message words are machine words; under voc's -O2
   model LONGINT is only 32 bits, so they are SYSTEM.ADDRESS here. *)

IMPORT SYSTEM;

CONST
  MaxWords* = 63;  (* Message registers per UTCB: L4_UTCB_GENERIC_DATA_SIZE *)

  Never* = 0;      (* Timeout: wait indefinitely (L4_IPC_NEVER) *)

  (* Rights for capabilities sent with PutCap, as L4_CAP_FPAGE_RO etc. *)
  CapRO*   = 4H;
  CapRW*   = 5H;
  CapRWS*  = 7H;
  CapRWSD* = 0FH;

  (* IPC failures are reported as -(IpcErrorBase + code), as by
     l4_ipc_to_errno; a reply's own label is reported as is. *)
  IpcErrorBase* = 2000;
  IpcErrorLast* = 2000 + 1FH;

  (* Message labels of kernel protocols, as L4_PROTO_FACTORY etc. *)
  ProtoFactory* = -15;

TYPE
  Cap*     = SYSTEM.ADDRESS;  (* l4_cap_idx_t *)
  Word*    = SYSTEM.ADDRESS;  (* l4_umword_t *)
  Timeout* = SYSTEM.INT32;    (* l4_timeout_t *)

  Message* = RECORD
    label*:  Word;     (* Protocol on requests, result on replies *)
    words*:  INTEGER;  (* Untyped words in mr *)
    items*:  INTEGER;  (* Capability items, sent after the words *)
    mr*:     ARRAY MaxWords OF Word;
    rcvCap*: Cap       (* Free slot to receive one capability into, or InvalidCap *)
  END;

VAR
  InvalidCap-: Cap;  (* L4_INVALID_CAP *)



PROCEDURE -Aincl1 '#include <l4/sys/consts.h>';
PROCEDURE -Aincl2 '#include <l4/sys/factory.h>';
PROCEDURE -Aincl3 '#include <l4/sys/ipc.h>';
PROCEDURE -Aincl4 '#include <l4/sys/kernel_object.h>';
PROCEDURE -Aincl5 '#include <l4/sys/rcv_endpoint.h>';
PROCEDURE -Aincl6 '#include <l4/sys/task.h>';
PROCEDURE -Aincl7 '#include <l4/sys/thread.h>';
PROCEDURE -Aincl8 '#include <l4/sys/types.h>';
PROCEDURE -Aincl9 '#include <l4/sys/utcb.h>';




(* Capabilities *)

PROCEDURE -invalidcap(): Cap "(ADDRESS)L4_INVALID_CAP";
PROCEDURE -capvalid(cap: Cap): BOOLEAN "!l4_is_invalid_cap((l4_cap_idx_t)(cap))";

PROCEDURE IsValid*(cap: Cap): BOOLEAN;
BEGIN RETURN capvalid(cap) END IsValid;

PROCEDURE IsIpcError*(e: LONGINT): BOOLEAN;
BEGIN RETURN (e <= -IpcErrorBase) & (e >= -IpcErrorLast) END IsIpcError;




(* Timeouts *)

PROCEDURE -timeoutus(us: SYSTEM.INT64): Timeout
"(INT32)l4_timeout(l4_timeout_from_us((l4_uint64_t)(us)), l4_timeout_from_us((l4_uint64_t)(us))).raw";

(* Both the send and the receive phase time out after us microseconds. *)
PROCEDURE After*(us: SYSTEM.INT64): Timeout;
BEGIN RETURN timeoutus(us) END After;




(* Building and reading messages *)

PROCEDURE Init*(VAR msg: Message; label: Word);
BEGIN
  msg.label := label; msg.words := 0; msg.items := 0; msg.rcvCap := InvalidCap
END Init;

(* Words must all be put before any capability. *)
PROCEDURE PutWord*(VAR msg: Message; w: Word);
BEGIN
  ASSERT((msg.items = 0) & (msg.words < MaxWords));
  msg.mr[msg.words] := w; INC(msg.words)
END PutWord;

(* A string travels as its length in a word, then its bytes packed into
   words, without the terminating 0X. FALSE if it does not fit. *)
PROCEDURE PutString*(VAR msg: Message; s: ARRAY OF CHAR): BOOLEAN;
  VAR len, n: LONGINT;
BEGIN
  ASSERT(msg.items = 0);
  len := 0; WHILE (len < LEN(s)) & (s[len] # 0X) DO INC(len) END;
  n := (len + SIZE(Word) - 1) DIV SIZE(Word);
  IF msg.words + 1 + n > MaxWords THEN RETURN FALSE END;
  msg.mr[msg.words] := len;
  IF len > 0 THEN SYSTEM.MOVE(SYSTEM.ADR(s), SYSTEM.ADR(msg.mr[msg.words + 1]), len) END;
  INC(msg.words, SHORT(1 + n));
  RETURN TRUE
END PutString;

(* Reads the string starting at word pos and advances pos past it. FALSE
   if the message is too short or s too small; pos is then unchanged. *)
PROCEDURE GetString*(VAR msg: Message; VAR pos: INTEGER; VAR s: ARRAY OF CHAR): BOOLEAN;
  VAR len, n: Word;
BEGIN
  IF (pos < 0) OR (pos >= msg.words) THEN RETURN FALSE END;
  len := msg.mr[pos];
  n := (len + SIZE(Word) - 1) DIV SIZE(Word);
  IF (len < 0) OR (len >= LEN(s)) OR (pos + 1 + n > msg.words) THEN RETURN FALSE END;
  IF len > 0 THEN SYSTEM.MOVE(SYSTEM.ADR(msg.mr[pos + 1]), SYSTEM.ADR(s), len) END;
  s[len] := 0X;
  INC(pos, SHORT(SHORT(1 + n)));
  RETURN TRUE
END GetString;


PROCEDURE -mapitem(): Word "(ADDRESS)l4_map_obj_control(0, 0)";
PROCEDURE -objfpage(cap: Cap; rights: LONGINT): Word
"(ADDRESS)l4_obj_fpage((l4_cap_idx_t)(cap), 0, (unsigned char)(rights)).raw";

(* Sends cap along with the message, with the given rights (CapRO...). *)
PROCEDURE PutCap*(VAR msg: Message; cap: Cap; rights: LONGINT);
  VAR w: INTEGER;
BEGIN
  w := msg.words + 2 * msg.items;
  ASSERT(w + 2 <= MaxWords);
  msg.mr[w] := mapitem(); msg.mr[w + 1] := objfpage(cap, rights);
  INC(msg.items)
END PutCap;




(* IPC *)

PROCEDURE -putmrs(src: SYSTEM.ADDRESS; n: LONGINT)
"memcpy(l4_utcb_mr()->mr, (void const*)(ADDRESS)(src), (size_t)(n) * sizeof(l4_umword_t))";
PROCEDURE -getmrs(dst: SYSTEM.ADDRESS; n: LONGINT)
"memcpy((void*)(ADDRESS)(dst), l4_utcb_mr()->mr, (size_t)(n) * sizeof(l4_umword_t))";

PROCEDURE -setrcv(cap: Cap)
"(l4_utcb_br()->bdr = 0, l4_utcb_br()->br[0] = l4_is_invalid_cap((l4_cap_idx_t)(cap)) ? 0 : ((l4_umword_t)(cap) | L4_RCV_ITEM_SINGLE_CAP))";

PROCEDURE -mktag(label: Word; words, items: LONGINT): Word
"(ADDRESS)l4_msgtag((long)(label), (unsigned)(words), (unsigned)(items), 0).raw";
PROCEDURE -taglabel(tag: Word): Word "(ADDRESS)l4_msgtag_label((l4_msgtag_t){.raw = (l4_mword_t)(tag)})";
PROCEDURE -tagwords(tag: Word): LONGINT "(INT32)l4_msgtag_words((l4_msgtag_t){.raw = (l4_mword_t)(tag)})";
PROCEDURE -tagitems(tag: Word): LONGINT "(INT32)l4_msgtag_items((l4_msgtag_t){.raw = (l4_mword_t)(tag)})";
(* Must be read straight after the IPC, before anything else uses the UTCB. *)
PROCEDURE -ipcerror(tag: Word): LONGINT
"(l4_msgtag_has_error((l4_msgtag_t){.raw = (l4_mword_t)(tag)}) ? (INT32)l4_ipc_to_errno(l4_ipc_error((l4_msgtag_t){.raw = (l4_mword_t)(tag)}, l4_utcb())) : 0)";

PROCEDURE -ipccall(dest: Cap; tag: Word; timeout: Timeout): Word
"(ADDRESS)l4_ipc_call((l4_cap_idx_t)(dest), l4_utcb(), (l4_msgtag_t){.raw = (l4_mword_t)(tag)}, (l4_timeout_t){.raw = (l4_uint32_t)(timeout)}).raw";
PROCEDURE -ipcsend(dest: Cap; tag: Word; timeout: Timeout): Word
"(ADDRESS)l4_ipc_send((l4_cap_idx_t)(dest), l4_utcb(), (l4_msgtag_t){.raw = (l4_mword_t)(tag)}, (l4_timeout_t){.raw = (l4_uint32_t)(timeout)}).raw";
PROCEDURE -ipcwait(VAR label: Word): Word
"(ADDRESS)l4_ipc_wait(l4_utcb(), (l4_umword_t*)(label), L4_IPC_NEVER).raw";
(* Replies without blocking on a client that is not receiving. *)
PROCEDURE -ipcreplywait(tag: Word; VAR label: Word): Word
"(ADDRESS)l4_ipc_reply_and_wait(l4_utcb(), (l4_msgtag_t){.raw = (l4_mword_t)(tag)}, (l4_umword_t*)(label), L4_IPC_SEND_TIMEOUT_0).raw";

PROCEDURE Load(VAR msg: Message): Word;
BEGIN
  ASSERT((msg.words >= 0) & (msg.items >= 0) & (msg.words + 2 * msg.items <= MaxWords));
  putmrs(SYSTEM.ADR(msg.mr), msg.words + 2 * msg.items);
  setrcv(msg.rcvCap);
  RETURN mktag(msg.label, msg.words, msg.items)
END Load;

(* Copies a received message out of the UTCB. The words of any capability
   items are not kept; the capabilities themselves are in msg.rcvCap. *)
PROCEDURE Store(tag: Word; VAR msg: Message);
  VAR n: LONGINT;
BEGIN
  n := tagwords(tag);
  msg.label := taglabel(tag); msg.words := SHORT(n); msg.items := SHORT(tagitems(tag));
  IF n > 0 THEN getmrs(SYSTEM.ADR(msg.mr), n) END
END Store;

(* Sends msg to dest and waits for the reply, which replaces msg. Returns a
   negative IPC error, otherwise the reply's label: 0 or a negative error by
   L4Re convention. *)
PROCEDURE Call*(dest: Cap; VAR msg: Message; timeout: Timeout): LONGINT;
  VAR tag: Word; e: LONGINT;
BEGIN
  tag := ipccall(dest, Load(msg), timeout);
  e := ipcerror(tag);
  IF e # 0 THEN RETURN e END;
  Store(tag, msg);
  RETURN SHORT(msg.label)
END Call;

(* Sends msg without waiting for a reply. 0 or a negative IPC error. *)
PROCEDURE Send*(dest: Cap; VAR msg: Message; timeout: Timeout): LONGINT;
BEGIN RETURN ipcerror(ipcsend(dest, Load(msg), timeout))
END Send;

(* Waits for a request on any gate bound to this thread. On success msg is
   the request and label the gate's label. 0 or a negative IPC error. A
   capability arrives only if msg.rcvCap names a free slot on entry. *)
PROCEDURE Wait*(VAR msg: Message; VAR label: Word): LONGINT;
  VAR tag: Word; e: LONGINT;
BEGIN
  setrcv(msg.rcvCap);
  tag := ipcwait(label);
  e := ipcerror(tag);
  IF e = 0 THEN Store(tag, msg) END;
  RETURN e
END Wait;

(* Sends msg as the reply to the last request, then waits for the next one,
   as Wait. If the reply cannot be delivered, nothing has been received:
   the result is negative and the caller should Wait again. *)
PROCEDURE ReplyAndWait*(VAR msg: Message; VAR label: Word): LONGINT;
  VAR tag: Word; e: LONGINT;
BEGIN
  tag := ipcreplywait(Load(msg), label);
  e := ipcerror(tag);
  IF e = 0 THEN Store(tag, msg) END;
  RETURN e
END ReplyAndWait;




(* IPC gates. Results are 0 or a negative L4 error. *)

PROCEDURE -l4error(tag: Word): LONGINT "(INT32)l4_error((l4_msgtag_t){.raw = (l4_mword_t)(tag)})";

PROCEDURE -creategate(factory, gate, thread: Cap; label: Word): Word
"(ADDRESS)l4_factory_create_gate((l4_cap_idx_t)(factory), (l4_cap_idx_t)(gate), (l4_cap_idx_t)(thread), (l4_umword_t)(label)).raw";
PROCEDURE -bindthread(gate, thread: Cap; label: Word): Word
"(ADDRESS)l4_rcv_ep_bind_thread((l4_cap_idx_t)(gate), (l4_cap_idx_t)(thread), (l4_umword_t)(label)).raw";

(* Creates an IPC gate in the free slot gate, bound to thread with label,
   or unbound if thread is InvalidCap. *)
PROCEDURE CreateGate*(factory, gate, thread: Cap; label: Word): LONGINT;
BEGIN RETURN l4error(creategate(factory, gate, thread, label))
END CreateGate;

(* Binds gate to thread: requests sent to it arrive at that thread's Wait
   with label. The kernel ORs the sender's rights into the low two bits of
   the label it delivers, so keep them zero here. *)
PROCEDURE BindThread*(gate, thread: Cap; label: Word): LONGINT;
BEGIN RETURN l4error(bindthread(gate, thread, label))
END BindThread;




(* Kernel objects. Results are 0 or a negative L4 error. *)

PROCEDURE -createirq(factory, irq: Cap): Word
"(ADDRESS)l4_factory_create_irq((l4_cap_idx_t)(factory), (l4_cap_idx_t)(irq)).raw";
PROCEDURE -registerdelirq(thread, irq: Cap): Word
"(ADDRESS)l4_thread_register_del_irq((l4_cap_idx_t)(thread), (l4_cap_idx_t)(irq)).raw";
PROCEDURE -decrefcnt(cap: Cap; n: LONGINT): Word
"(ADDRESS)l4_kobject_dec_refcnt((l4_cap_idx_t)(cap), (l4_mword_t)(n)).raw";
PROCEDURE -capexists(cap: Cap): BOOLEAN
"(l4_msgtag_label(l4_task_cap_valid(L4_BASE_TASK_CAP, (l4_cap_idx_t)(cap))) > 0)";

(* Creates an IRQ object in the free slot irq. Bind it to a thread with
   BindThread to receive its triggers there. *)
PROCEDURE CreateIrq*(factory, irq: Cap): LONGINT;
BEGIN RETURN l4error(createirq(factory, irq))
END CreateIrq;

(* Has irq triggered whenever an IPC gate bound to thread is deleted. The
   trigger does not say which gate. *)
PROCEDURE RegisterDeletionIrq*(thread, irq: Cap): LONGINT;
BEGIN RETURN l4error(registerdelirq(thread, irq))
END RegisterDeletionIrq;

(* Stops n of this task's references to the object in cap counting toward
   keeping it alive, so it is deleted once the others are gone. *)
PROCEDURE DecRefcnt*(cap: Cap; n: LONGINT): LONGINT;
BEGIN RETURN l4error(decrefcnt(cap, n))
END DecRefcnt;

(* Whether cap still refers to an object; FALSE once the object has been
   deleted. *)
PROCEDURE Exists*(cap: Cap): BOOLEAN;
BEGIN RETURN capexists(cap)
END Exists;


BEGIN
  InvalidCap := invalidcap()
END L4.
