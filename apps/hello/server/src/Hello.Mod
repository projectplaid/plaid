MODULE Hello;

IMPORT Out, Platform;

BEGIN
  LOOP
    Out.String("Hello World!"); Out.Ln;
    Platform.Delay(1000)
  END
END Hello.
