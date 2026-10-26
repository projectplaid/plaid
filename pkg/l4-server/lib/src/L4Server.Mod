MODULE L4Server;

(* Objects served over IPC gates, and the loop that serves them.

   An Object is reached through its gate; the gate's label is the object's
   address, so a request goes straight to its Dispatch. The kernel's copy
   of that address is invisible to the GC, so this module keeps every
   registered object alive until it is unregistered (voc's heap never
   moves objects).

   Sessions are objects whose gate only clients keep alive, as moe does
   it: once the last client capability to a session is gone the kernel
   deletes its gate, the deletion IRQ fires, and the loop calls the
   session's Closed and unregisters it.

   Everything runs on the main thread; voc's runtime is single-threaded. *)

IMPORT SYSTEM, L4, L4Re;

CONST
  ENOMEM = 12;
  ENODEV = 19;
  EINVAL = 22;
  ENOSYS = 38;

  (* Label of the deletion IRQ: low bits clear, and below any heap address. *)
  IrqLabel = 4;

TYPE
  Object* = POINTER TO ObjectDesc;
  ObjectDesc* = RECORD
    gate-:   L4.Cap;   (* Where clients reach the object; L4.InvalidCap when not served *)
    session: BOOLEAN;
    next:    Object
  END;

  (* Serves the L4 factory protocol: ned's create, or an L4.ProtoFactory
     request, makes a session through NewSession and hands back its gate. *)
  Factory* = POINTER TO FactoryDesc;
  FactoryDesc* = RECORD (ObjectDesc) END;

VAR
  objects: Object;   (* Every registered object, which also keeps it alive *)
  rcvSlot: L4.Cap;   (* Receive window for a capability sent with a request *)
  taken:   BOOLEAN;  (* The current request's capability was kept by TakeCap *)
  delIrq:  L4.Cap;   (* Deletion IRQ, created with the first session *)




(* Methods to override *)

(* Turns the request in msg into its reply, in place. rights are the two
   low bits the kernel adds to the label: the client capability's write and
   special rights. A capability sent with the request is in msg.rcvCap when
   msg.items > 0; it is dropped after Dispatch unless TakeCap keeps it. *)
PROCEDURE (o: Object) Dispatch*(VAR msg: L4.Message; rights: LONGINT);
BEGIN L4.Init(msg, -ENOSYS)
END Dispatch;

(* Called when o's gate is gone: a session whose clients all dropped it.
   o is unregistered afterwards. *)
PROCEDURE (o: Object) Closed*;
BEGIN
END Closed;

(* A new session for a create request asking for type, or NIL to refuse
   it. msg is the request: type is in mr[0], the arguments follow. *)
PROCEDURE (f: Factory) NewSession*(type: L4.Word; VAR msg: L4.Message): Object;
BEGIN RETURN NIL
END NewSession;




(* Registry *)

PROCEDURE Label(o: Object): L4.Word;
BEGIN RETURN SYSTEM.VAL(L4.Word, o)
END Label;

PROCEDURE Add(o: Object; gate: L4.Cap; session: BOOLEAN);
BEGIN
  o.gate := gate; o.session := session;
  o.next := objects; objects := o
END Add;

PROCEDURE Remove(o: Object);
  VAR p: Object;
BEGIN
  IF objects = o THEN objects := o.next
  ELSE
    p := objects;
    WHILE (p # NIL) & (p.next # o) DO p := p.next END;
    IF p # NIL THEN p.next := o.next END
  END;
  o.next := NIL; o.gate := L4.InvalidCap
END Remove;

(* Serves o on gate, an existing IPC gate, such as one passed in by ned
   (L4Re.GetCap). Results are 0 or a negative L4 error. *)
PROCEDURE Register*(o: Object; gate: L4.Cap): LONGINT;
  VAR e: LONGINT;
BEGIN
  ASSERT(Label(o) MOD 4 = 0);
  e := L4.BindThread(gate, L4Re.MainThread(), Label(o));
  IF e = 0 THEN Add(o, gate, FALSE) END;
  RETURN e
END Register;

PROCEDURE NewGate(o: Object; VAR gate: L4.Cap): LONGINT;
  VAR e: LONGINT;
BEGIN
  ASSERT(Label(o) MOD 4 = 0);
  gate := L4Re.AllocCap();
  IF ~L4.IsValid(gate) THEN RETURN -ENOMEM END;
  e := L4.CreateGate(L4Re.Factory(), gate, L4Re.MainThread(), Label(o));
  IF e # 0 THEN L4Re.FreeCap(gate) END;
  RETURN e
END NewGate;

(* Serves o on a new gate, o.gate, for this program to hand out with
   L4.PutCap. It stays until Unregister. *)
PROCEDURE Create*(o: Object): LONGINT;
  VAR e: LONGINT; gate: L4.Cap;
BEGIN
  e := NewGate(o, gate);
  IF e = 0 THEN Add(o, gate, FALSE) END;
  RETURN e
END Create;

PROCEDURE EnsureDeletionIrq(): LONGINT;
  VAR e: LONGINT;
BEGIN
  IF L4.IsValid(delIrq) THEN RETURN 0 END;
  delIrq := L4Re.AllocCap();
  IF ~L4.IsValid(delIrq) THEN RETURN -ENOMEM END;
  e := L4.CreateIrq(L4Re.Factory(), delIrq);
  IF e = 0 THEN e := L4.BindThread(delIrq, L4Re.MainThread(), IrqLabel) END;
  IF e = 0 THEN e := L4.RegisterDeletionIrq(L4Re.MainThread(), delIrq) END;
  IF e # 0 THEN L4Re.ReleaseCap(delIrq); delIrq := L4.InvalidCap END;
  RETURN e
END EnsureDeletionIrq;

(* Like Create, but only clients keep the gate alive: hand o.gate out with
   L4.PutCap straight away. Once the last client capability is gone, o's
   Closed is called and o unregistered. *)
PROCEDURE CreateSession*(o: Object): LONGINT;
  VAR e: LONGINT; gate: L4.Cap;
BEGIN
  e := EnsureDeletionIrq();
  IF e = 0 THEN e := NewGate(o, gate) END;
  IF e = 0 THEN
    e := L4.DecRefcnt(gate, 1);
    IF e = 0 THEN Add(o, gate, TRUE) ELSE L4Re.ReleaseCap(gate) END
  END;
  RETURN e
END CreateSession;

(* Stops serving o and drops its gate. Clients still holding a capability
   to it get IPC errors. *)
PROCEDURE Unregister*(o: Object);
  VAR gate: L4.Cap;
BEGIN
  gate := o.gate; Remove(o);
  IF L4.IsValid(gate) THEN L4Re.ReleaseCap(gate) END
END Unregister;

(* Keeps the capability that came with the current request; call it from
   Dispatch. Returns its slot, now the caller's. *)
PROCEDURE TakeCap*(): L4.Cap;
  VAR cap: L4.Cap;
BEGIN
  cap := rcvSlot; taken := TRUE;
  rcvSlot := L4Re.AllocCap();
  RETURN cap
END TakeCap;




(* Factory protocol *)

PROCEDURE (f: Factory) Dispatch*(VAR msg: L4.Message; rights: LONGINT);
  VAR s: Object; e: LONGINT;
BEGIN
  IF msg.label # L4.ProtoFactory THEN L4.Init(msg, -ENOSYS)
  ELSIF msg.words < 1 THEN L4.Init(msg, -EINVAL)
  ELSE
    s := f.NewSession(msg.mr[0], msg);
    IF s = NIL THEN L4.Init(msg, -ENODEV)
    ELSE
      e := CreateSession(s);
      L4.Init(msg, e);
      IF e = 0 THEN L4.PutCap(msg, s.gate, L4.CapRWSD) END
    END
  END
END Dispatch;




(* The loop *)

(* Closes every session whose gate the kernel has deleted. *)
PROCEDURE Sweep;
  VAR o, next: Object; gate: L4.Cap;
BEGIN
  o := objects;
  WHILE o # NIL DO
    next := o.next;
    IF o.session & ~L4.Exists(o.gate) THEN
      gate := o.gate; Remove(o);
      L4Re.FreeCap(gate);  (* The slot is already empty. *)
      o.Closed
    END;
    o := next
  END
END Sweep;

(* Serves requests on every registered gate. Does not return. *)
PROCEDURE Run*;
  VAR
    msg: L4.Message; label: L4.Word; e: LONGINT;
    o: Object; hadCap, reply: BOOLEAN;
BEGIN
  IF ~L4.IsValid(rcvSlot) THEN rcvSlot := L4Re.AllocCap() END;
  L4.Init(msg, 0); msg.rcvCap := rcvSlot;
  e := L4.Wait(msg, label);
  LOOP
    reply := FALSE;
    IF e = 0 THEN
      IF label - label MOD 4 = IrqLabel THEN Sweep
      ELSE
        o := SYSTEM.VAL(Object, label - label MOD 4);
        hadCap := msg.items > 0; taken := FALSE;
        o.Dispatch(msg, SHORT(label MOD 4));
        IF hadCap & ~taken THEN
          L4Re.ReleaseCap(rcvSlot); rcvSlot := L4Re.AllocCap()
        END;
        reply := TRUE
      END
    END;
    (* A failed reply received nothing: fall back to a plain Wait. *)
    IF reply THEN
      msg.rcvCap := rcvSlot;
      e := L4.ReplyAndWait(msg, label)
    ELSE
      L4.Init(msg, 0); msg.rcvCap := rcvSlot;
      e := L4.Wait(msg, label)
    END
  END
END Run;


BEGIN
  objects := NIL;
  rcvSlot := L4.InvalidCap;
  delIrq  := L4.InvalidCap
END L4Server.
