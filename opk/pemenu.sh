#!/bin/sh
# Raise the in-game quick menu.
#
# fkgpiod runs this from a COMMAND mapping, which is the one input path that
# still works while the game owns the screen -- the daemon executes it itself
# rather than delivering a key. It signals whichever process opkrun registered
# as the foreground app, which for this port is the OPK's run.sh, whose SIGUSR1
# trap opens the menu.
kill -USR1 "$(/usr/local/sbin/pid print 2>/dev/null)" 2>/dev/null
