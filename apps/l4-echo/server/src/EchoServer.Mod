MODULE EchoServer;

(* Test service for modules L4 and L4Server. The gate passed in as "echo"
   is a factory: each create request opens a session, which answers OpEcho
   with the string reversed and OpShare with a dataspace it has written a
   string into, and OpSize with the size of a dataspace sent along with it.
   The factory itself answers OpSessions with the number of open sessions,
   so a client can watch its session close. *)

IMPORT SYSTEM, Out, L4, L4Re, L4Server;

CONST
  Proto      = 5100H;  (* Must match EchoClient. *)
  OpEcho     = 1;
  OpShare    = 2;
  OpSessions = 3;
  OpSize     = 4;

  EINVAL = 22;
  ENOSYS = 38;

  SharedSize = 4096;
  SharedText = "written by the echo server into a shared dataspace";

TYPE
  Session = POINTER TO SessionDesc;
  SessionDesc = RECORD (L4Server.ObjectDesc)
    id: INTEGER
  END;

  EchoFactory = POINTER TO EchoFactoryDesc;
  EchoFactoryDesc = RECORD (L4Server.FactoryDesc) END;

VAR
  shared: L4.Cap;
  opened, open: INTEGER;  (* Sessions ever opened, and still open *)
  factory: EchoFactory;


PROCEDURE Fail(what: ARRAY OF CHAR; e: LONGINT);
BEGIN
  Out.String("echo server: "); Out.String(what); Out.String(" failed: ");
  Out.Int(e, 0); Out.Ln; HALT(1)
END Fail;

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

PROCEDURE (s: Session) Dispatch*(VAR msg: L4.Message; rights: LONGINT);
  VAR size: SYSTEM.ADDRESS;
BEGIN
  IF (msg.label # Proto) OR (msg.words < 1) THEN L4.Init(msg, -EINVAL)
  ELSIF msg.mr[0] = OpEcho THEN Echo(msg)
  ELSIF msg.mr[0] = OpShare THEN
    L4.Init(msg, 0); L4.PutWord(msg, SharedSize); L4.PutCap(msg, shared, L4.CapRW)
  ELSIF msg.mr[0] = OpSize THEN
    (* The loop drops the capability afterwards; TakeCap would keep it. *)
    IF msg.items # 1 THEN L4.Init(msg, -EINVAL)
    ELSE size := L4Re.DataspaceSize(msg.rcvCap); L4.Init(msg, 0); L4.PutWord(msg, size)
    END
  ELSE L4.Init(msg, -ENOSYS)
  END
END Dispatch;

PROCEDURE (s: Session) Closed*;
BEGIN
  DEC(open);
  Out.String("echo server: session "); Out.Int(s.id, 0); Out.String(" closed"); Out.Ln
END Closed;

PROCEDURE (f: EchoFactory) NewSession*(type: L4.Word; VAR msg: L4.Message): L4Server.Object;
  VAR s: Session;
BEGIN
  NEW(s); INC(opened); INC(open); s.id := opened;
  Out.String("echo server: session "); Out.Int(s.id, 0); Out.String(" opened"); Out.Ln;
  RETURN s
END NewSession;

PROCEDURE (f: EchoFactory) Dispatch*(VAR msg: L4.Message; rights: LONGINT);
BEGIN
  IF (msg.label = Proto) & (msg.words >= 1) & (msg.mr[0] = OpSessions) THEN
    L4.Init(msg, 0); L4.PutWord(msg, open)
  ELSE f.Dispatch^(msg, rights)
  END
END Dispatch;

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

PROCEDURE Start;
  VAR gate: L4.Cap; e: LONGINT;
BEGIN
  gate := L4Re.GetCap("echo");
  IF ~L4.IsValid(gate) THEN Fail("finding the echo capability", 0) END;
  SetUpShared;
  NEW(factory);
  e := L4Server.Register(factory, gate);
  IF e # 0 THEN Fail("registering the factory", e) END;
  Out.String("echo server: ready"); Out.Ln;
  L4Server.Run
END Start;

BEGIN
  opened := 0; open := 0;
  Start
END EchoServer.
