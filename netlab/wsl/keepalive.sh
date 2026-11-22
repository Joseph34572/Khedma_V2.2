#!/bin/bash
# keepalive.sh - keeps the NetLab WSL distro running while a lab is up.
#
# WSL stops a distro about 15 s after the last program started from Windows
# exits, and that would kill Docker and the lab. The Windows menu starts this
# script hidden after a deploy and stops it after a destroy, so the distro (and
# its RAM) goes away as soon as no lab is running.
exec -a netlab-keepalive sleep infinity
