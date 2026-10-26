MODULE EchoClient;

(* Test client for modules L4 and L4Server: exercises an EchoServer session
   that ned created ("session"), then one it creates itself through the
   factory ("echo"), drops that one and waits for the server to close it.
   Reports "l4-echo: passed" or the first failure. *)

IMPORT SYSTEM, Out, Platform, L4, L4Re;

CONST
  Proto      = 5100H;  (* Must match EchoServer. *)
  OpEcho     = 1;
  OpShare    = 2;
  OpSessions = 3;
  OpSize     = 4;
  OpNone     = 99;

  ENOSYS = 38;

  Text     = "Hello from Oberon";
  Reversed = "norebO morf olleH";
  Shared   = "written by the echo server into a shared dataspace";

VAR
  failed: BOOLEAN;


PROCEDURE Fail(what: ARRAY OF CHAR; e: LONGINT);
BEGIN
  Out.String("l4-echo: FAILED: "); Out.String(what);
  Out.String(" ("); Out.Int(e, 0); Out.String(")"); Out.Ln;
  failed := TRUE
END Fail;

PROCEDURE Call(gate: L4.Cap; VAR msg: L4.Message): LONGINT;
BEGIN RETURN L4.Call(gate, msg, L4.After(1000000))
END Call;

PROCEDURE TestEcho(session: L4.Cap);
  VAR msg: L4.Message; e: LONGINT; pos: INTEGER; reply: ARRAY 64 OF CHAR;
BEGIN
  L4.Init(msg, Proto); L4.PutWord(msg, OpEcho);
  IF ~L4.PutString(msg, Text) THEN Fail("building the echo request", 0); RETURN END;
  e := Call(session, msg);
  IF e # 0 THEN Fail("echo call", e); RETURN END;
  pos := 0;
  IF ~L4.GetString(msg, pos, reply) THEN Fail("reading the echo reply", msg.words); RETURN END;
  IF reply # Reversed THEN Fail("echo reply is wrong", 0) END
END TestEcho;

PROCEDURE TestShare(session: L4.Cap);
  VAR
    msg: L4.Message; e: LONGINT; ds: L4.Cap;
    address: SYSTEM.ADDRESS; text: ARRAY 64 OF CHAR; i: INTEGER;
BEGIN
  L4.Init(msg, Proto); L4.PutWord(msg, OpShare);
  ds := L4Re.AllocCap(); msg.rcvCap := ds;
  e := Call(session, msg);
  IF e # 0 THEN Fail("share call", e); RETURN END;
  IF (msg.items # 1) OR (msg.words # 1) THEN Fail("share reply has no capability", msg.items); RETURN END;
  e := L4Re.Attach(ds, msg.mr[0], address);
  IF e # 0 THEN Fail("attaching the shared dataspace", e); RETURN END;
  i := 0;
  REPEAT SYSTEM.GET(address + i, text[i]); INC(i) UNTIL (text[i - 1] = 0X) OR (i = LEN(text));
  text[LEN(text) - 1] := 0X;
  IF text # Shared THEN Fail("shared dataspace text is wrong", 0) END;
  e := L4Re.Detach(address, ds);
  L4Re.ReleaseCap(ds)
END TestShare;

PROCEDURE TestSendCap(session: L4.Cap);
  CONST Size = 3 * 4096;
  VAR msg: L4.Message; e: LONGINT; ds: L4.Cap;
BEGIN
  e := L4Re.AllocDataspace(Size, ds);
  IF e # 0 THEN Fail("allocating a dataspace to send", e); RETURN END;
  L4.Init(msg, Proto); L4.PutWord(msg, OpSize); L4.PutCap(msg, ds, L4.CapRO);
  e := Call(session, msg);
  IF e # 0 THEN Fail("size call", e)
  ELSIF (msg.words # 1) OR (msg.mr[0] # Size) THEN Fail("server saw the wrong size", SHORT(msg.mr[0]))
  END;
  L4Re.ReleaseCap(ds)
END TestSendCap;

PROCEDURE TestUnknownOp(session: L4.Cap);
  VAR msg: L4.Message; e: LONGINT;
BEGIN
  L4.Init(msg, Proto); L4.PutWord(msg, OpNone);
  e := Call(session, msg);
  IF e # -ENOSYS THEN Fail("unknown op should give -ENOSYS", e) END
END TestUnknownOp;

PROCEDURE TestSession(session: L4.Cap; name: ARRAY OF CHAR);
BEGIN
  TestEcho(session); TestShare(session); TestSendCap(session); TestUnknownOp(session);
  IF ~failed THEN
    Out.String("l4-echo: "); Out.String(name); Out.String(" session works"); Out.Ln
  END
END TestSession;

(* The factory's count of open sessions, or -1. *)
PROCEDURE Sessions(factory: L4.Cap): LONGINT;
  VAR msg: L4.Message;
BEGIN
  L4.Init(msg, Proto); L4.PutWord(msg, OpSessions);
  IF (Call(factory, msg) # 0) OR (msg.words # 1) THEN RETURN -1 END;
  RETURN SHORT(msg.mr[0])
END Sessions;

(* Opens a session through the L4 factory protocol, as ned's create does. *)
PROCEDURE CreateSession(factory: L4.Cap; VAR session: L4.Cap): LONGINT;
  VAR msg: L4.Message; e: LONGINT;
BEGIN
  L4.Init(msg, L4.ProtoFactory); L4.PutWord(msg, 0);
  session := L4Re.AllocCap(); msg.rcvCap := session;
  e := Call(factory, msg);
  IF (e = 0) & (msg.items # 1) THEN e := -1 END;
  IF e # 0 THEN L4Re.FreeCap(session); session := L4.InvalidCap END;
  RETURN e
END CreateSession;

PROCEDURE TestOwnSession(factory: L4.Cap);
  VAR session: L4.Cap; e, before, n: LONGINT; tries: INTEGER;
BEGIN
  before := Sessions(factory);
  e := CreateSession(factory, session);
  IF e # 0 THEN Fail("creating a session", e); RETURN END;
  n := Sessions(factory);
  IF n # before + 1 THEN Fail("session count after create", n) END;
  TestSession(session, "own");
  (* Dropping the only capability deletes the gate; the server notices. *)
  L4Re.ReleaseCap(session);
  tries := 0;
  REPEAT Platform.Delay(10); n := Sessions(factory); INC(tries)
  UNTIL (n = before) OR (tries = 200);
  IF n # before THEN Fail("server did not close the dropped session", n)
  ELSE Out.String("l4-echo: dropped session was closed"); Out.Ln
  END
END TestOwnSession;

PROCEDURE Main;
  VAR factory, session: L4.Cap;
BEGIN
  factory := L4Re.GetCap("echo"); session := L4Re.GetCap("session");
  IF ~L4.IsValid(factory) OR ~L4.IsValid(session) THEN Fail("missing capabilities", 0); RETURN END;
  TestSession(session, "ned's");
  IF ~failed THEN TestOwnSession(factory) END
END Main;

BEGIN
  failed := FALSE;
  Main;
  IF ~failed THEN Out.String("l4-echo: passed"); Out.Ln END
END EchoClient.
