MODULE EchoServer;

(* Test service for module L4. On the gate passed in as "echo" it answers
   OpEcho with the string reversed, and OpShare with a dataspace it has
   written a string into. *)

IMPORT SYSTEM, Out, L4, L4Re;

CONST
  Proto   = 5100H;  (* Must match EchoClient. *)
  OpEcho  = 1;
  OpShare = 2;

  GateLabel = 10H;

  EINVAL    = 22;
  ENOSYS    = 38;
  EBADPROTO = 39;

  SharedSize = 4096;
  SharedText = "written by the echo server into a shared dataspace";

VAR
  gate, shared: L4.Cap;


PROCEDURE Echo(VAR msg: L4.Message);
  VAR s, r: ARRAY 256 OF CHAR; pos, i, n: INTEGER;
BEGIN
  pos := 1;
  IF ~L4.GetString(msg, pos, s) THEN L4.Init(msg, -EINVAL); RETURN END;
  n := 0; WHILE s[n] # 0X DO INC(n) END;
  FOR i := 0 TO n - 1 DO r[i] := s[n - 1 - i] END;
  r[n] := 0X;
  L4.Init(msg, 0);
  IF ~L4.PutString(msg, r) THEN L4.Init(msg, -EINVAL) END
END Echo;

PROCEDURE Share(VAR msg: L4.Message);
BEGIN
  L4.Init(msg, 0);
  L4.PutWord(msg, SharedSize);
  L4.PutCap(msg, shared, L4.CapRW)
END Share;

(* Turns the request in msg into its reply. *)
PROCEDURE Handle(VAR msg: L4.Message);
BEGIN
  IF msg.label # Proto THEN L4.Init(msg, -EBADPROTO)
  ELSIF msg.words < 1 THEN L4.Init(msg, -EINVAL)
  ELSIF msg.mr[0] = OpEcho THEN Echo(msg)
  ELSIF msg.mr[0] = OpShare THEN Share(msg)
  ELSE L4.Init(msg, -ENOSYS)
  END
END Handle;

PROCEDURE Fail(what: ARRAY OF CHAR; e: LONGINT);
BEGIN
  Out.String("echo server: "); Out.String(what); Out.String(" failed: ");
  Out.Int(e, 0); Out.Ln; HALT(1)
END Fail;

PROCEDURE Serve(gate: L4.Cap);
  VAR msg: L4.Message; label: L4.Word; e: LONGINT;
BEGIN
  e := L4.BindThread(gate, L4Re.MainThread(), GateLabel);
  IF e # 0 THEN Fail("binding the gate", e) END;
  Out.String("echo server: ready"); Out.Ln;
  L4.Init(msg, 0);
  e := L4.Wait(msg, label);
  LOOP
    IF e = 0 THEN
      IF SYSTEM.VAL(SET, label) - {0, 1} # SYSTEM.VAL(SET, GateLabel) THEN
        Out.String("echo server: unexpected label "); Out.Int(label, 0); Out.Ln
      END;
      Handle(msg);
      e := L4.ReplyAndWait(msg, label)
    ELSE
      Out.String("echo server: IPC error "); Out.Int(e, 0); Out.Ln;
      L4.Init(msg, 0);
      e := L4.Wait(msg, label)
    END
  END
END Serve;

PROCEDURE SetUpShared;
  VAR e: LONGINT; address: SYSTEM.ADDRESS; text: ARRAY 64 OF CHAR;
BEGIN
  e := L4Re.AllocDataspace(SharedSize, shared);
  IF e # 0 THEN Fail("allocating the dataspace", e) END;
  e := L4Re.Attach(shared, SharedSize, address);
  IF e # 0 THEN Fail("attaching the dataspace", e) END;
  text := SharedText;
  SYSTEM.MOVE(SYSTEM.ADR(text), address, LEN(text))
END SetUpShared;

BEGIN
  gate := L4Re.GetCap("echo");
  IF ~L4.IsValid(gate) THEN Out.String("echo server: no echo capability"); Out.Ln; HALT(1) END;
  SetUpShared;
  Serve(gate)
END EchoServer.
