---
title: Remote kiosk debugging
section: Kiosk / Remote debug
source_path: setup/cli/startx.sh
---

# Remote kiosk debugging

Start the X server only from its intended local console session. After that
session is running, an SSH session for the same user can attach an application
to the existing display by setting the appropriate display and user runtime
environment.

```bash
export DISPLAY=:0
export XAUTHORITY=/home/app/.Xauthority
export XDG_RUNTIME_DIR=/run/user/$(id -u app)
```

This is a debugging workflow, not a mechanism for starting an X server over
SSH. Check the target application’s display and authentication expectations
before attaching it.
