MODULE EchoClient;

(* Test client for module L4: exercises EchoServer over the gate passed in
   as "echo" and reports "l4-echo: passed" or the first failure. *)

IMPORT SYSTEM, Out, Platform, L4, L4Re;

CONST
  Proto   = 5100H;  (* Must match EchoServer. *)
  OpEcho  = 1;
  OpShare = 2;
  OpNone  = 99;

  ENOSYS = 38;

  Text     = "Hello from Oberon";
  Reversed = "norebO morf olleH";
  Shared   = "written by the echo server into a shared dataspace";

VAR
  gate: L4.Cap;
  failed: BOOLEAN;


PROCEDURE Fail(what: ARRAY OF CHAR; e: LONGINT);
BEGIN
  Out.String("l4-echo: FAILED: "); Out.String(what);
  Out.String(" ("); Out.Int(e, 0); Out.String(")"); Out.Ln;
  failed := TRUE
END Fail;

(* The server may not have bound the gate yet when we start. *)
PROCEDURE Call(VAR msg: L4.Message): LONGINT;
  VAR e: LONGINT; tries: INTEGER;
BEGIN
  tries := 0;
  REPEAT
    e := L4.Call(gate, msg, L4.After(1000000));
    IF L4.IsIpcError(e) THEN Platform.Delay(100) END;
    INC(tries)
  UNTIL ~L4.IsIpcError(e) OR (tries = 50);
  RETURN e
END Call;

PROCEDURE TestEcho;
  VAR msg: L4.Message; e: LONGINT; pos: INTEGER; reply: ARRAY 64 OF CHAR;
BEGIN
  L4.Init(msg, Proto); L4.PutWord(msg, OpEcho);
  IF ~L4.PutString(msg, Text) THEN Fail("building the echo request", 0); RETURN END;
  e := Call(msg);
  IF e # 0 THEN Fail("echo call", e); RETURN END;
  pos := 0;
  IF ~L4.GetString(msg, pos, reply) THEN Fail("reading the echo reply", msg.words); RETURN END;
  Out.String("l4-echo: echo replied '"); Out.String(reply); Out.String("'"); Out.Ln;
  IF reply # Reversed THEN Fail("echo reply is wrong", 0) END
END TestEcho;

PROCEDURE TestShare;
  VAR
    msg: L4.Message; e: LONGINT; ds: L4.Cap;
    address: SYSTEM.ADDRESS; text: ARRAY 64 OF CHAR; i: INTEGER;
BEGIN
  L4.Init(msg, Proto); L4.PutWord(msg, OpShare);
  ds := L4Re.AllocCap(); msg.rcvCap := ds;
  e := Call(msg);
  IF e # 0 THEN Fail("share call", e); RETURN END;
  IF (msg.items # 1) OR (msg.words # 1) THEN Fail("share reply has no capability", msg.items); RETURN END;
  e := L4Re.Attach(ds, msg.mr[0], address);
  IF e # 0 THEN Fail("attaching the shared dataspace", e); RETURN END;
  i := 0;
  REPEAT SYSTEM.GET(address + i, text[i]); INC(i) UNTIL (text[i - 1] = 0X) OR (i = LEN(text));
  text[LEN(text) - 1] := 0X;
  Out.String("l4-echo: shared dataspace says '"); Out.String(text); Out.String("'"); Out.Ln;
  IF text # Shared THEN Fail("shared dataspace text is wrong", 0) END;
  e := L4Re.Detach(address, ds);
  L4Re.ReleaseCap(ds)
END TestShare;

PROCEDURE TestUnknownOp;
  VAR msg: L4.Message; e: LONGINT;
BEGIN
  L4.Init(msg, Proto); L4.PutWord(msg, OpNone);
  e := Call(msg);
  IF e # -ENOSYS THEN Fail("unknown op should give -ENOSYS", e) END
END TestUnknownOp;

BEGIN
  failed := FALSE;
  gate := L4Re.GetCap("echo");
  IF ~L4.IsValid(gate) THEN Fail("no echo capability", 0)
  ELSE TestEcho; TestShare; TestUnknownOp
  END;
  IF ~failed THEN Out.String("l4-echo: passed"); Out.Ln END
END EchoClient.
