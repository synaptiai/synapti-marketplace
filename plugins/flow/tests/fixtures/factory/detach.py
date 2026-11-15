"""Run a command in a new session, with no controlling terminal, as launchd
and cron start a job: detach.py <command> [arguments]."""
import os
import sys

pid = os.fork()
if pid == 0:
    os.setsid()
    os.execvp(sys.argv[1], sys.argv[1:])
_, status = os.waitpid(pid, 0)
sys.exit(os.waitstatus_to_exitcode(status))
