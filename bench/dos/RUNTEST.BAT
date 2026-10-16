@ECHO OFF
REM RUNTEST name - run C:\BENCH\TESTS\name.BAT once per run.
REM A test still marked as running after a reboot hung the PC: it is skipped and noted.
IF NOT EXIST C:\BENCH\TESTS\%1.BAT GOTO END
IF EXIST %S%\%1.OK GOTO END
IF EXIST %S%\%1.ERR GOTO END
IF EXIST %S%\%1.RUN GOTO HUNG
ECHO %1> %S%\%1.RUN
ECHO BENCH: %1
CALL C:\BENCH\TESTS\%1.BAT
REN %S%\%1.RUN %1.OK
GOTO END
:HUNG
REN %S%\%1.RUN %1.ERR
ECHO %1=hung>> %R%\ERRORS.INI
:END
CD \
