# shellcheck shell=bash
# [flow] lib/tier-factory.sh — the flow factory's own rules for Bash commands,
# sourced by hooks/scripts/tier-gate.sh.
#
# tier-gate.sh sources this file only in a factory (a FLOW_FACTORY_JOB,
# _DIRECTIVE, _IO or _MAIN variable in its environment, or the directory
# <main checkout>/<runtime dir>/factory for the command's repository), and
# only for a payload that names flow-factory, _flow_factory or /factory. It
# does so before it needs jq, before it reads the command, and before any
# ask, breadcrumb or approval record is written.
#
# The contract with tier-gate.sh:
#   _tg_factory_rules is called with no arguments. INPUT holds the raw hook
#   payload (it may not be valid JSON, and jq may be missing); SCRIPT_DIR is
#   hooks/scripts and PLUGIN_ROOT the plugin's root.
#   To leave the decision to the rest of tier-gate.sh it returns.
#   To decide, it prints one PreToolUse decision and exits 0. `_tg_deny
#   <reason>` prints a deny without jq and exits; a deny is the answer for
#   the whole command, whatever else the command does.
#
# This version has no rules of its own: it leaves every decision to
# tier-gate.sh. The rules for worker sessions, person commands, the factory
# directory and person commands posted as comments replace this body.

_tg_factory_rules() {
  return 0
}
