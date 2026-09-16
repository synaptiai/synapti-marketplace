#!/usr/bin/env bash
# [flow] Name the contract files in a list of changed paths.
#
# A change to a contract is a change to something other code depends on, so the
# review lists who depends on it (`### Blast radius` in the review body) and
# every consumer either appears in the diff or earns a `breaking-change`
# finding. This script answers only the first question — which changed paths ARE
# contracts — and answers it by path and extension alone.
#
# It deliberately does not parse any of these formats. Resolving an OpenAPI
# `$ref`, walking a GraphQL schema or reading a protobuf message would let it
# name consumers precisely, and would also be a parser per format that this
# repository has no way to exercise. Naming the file is what the reviewer needs;
# finding the consumers is the reviewer's own step, with Grep and the LSP.
#
# Cross-repository consumers are out of scope: flow has no linked-repository
# model (#213 non-goal).
#
# Usage:
#   flow-contract-files.sh <path>...      # paths as arguments
#   git diff --name-only | flow-contract-files.sh   # or on stdin
#
# Output: one line per contract file, in input order:
#   CONTRACT_FILE=<path>|<kind>
# kind is one of: openapi, graphql, protobuf, migration, schema, goal-contract.
#
# Exits:
#   0 — at least one contract file was named
#   1 — none of the paths is a contract file
#   2 — usage error

set -uo pipefail

PROG="flow-contract-files.sh"

case "${1:-}" in
  -h|--help)
    echo "usage: $PROG <path>... | <paths on stdin>" >&2
    exit 2
    ;;
esac

# Classify one path. Bracket ranges follow the locale, so match under C.
kind_of() {
  local LC_ALL=C p="$1" base
  base=${p##*/}

  case "$base" in
    # An OpenAPI or Swagger document, by the names the tooling recognises.
    openapi.yaml|openapi.yml|openapi.json|swagger.yaml|swagger.yml|swagger.json)
      echo openapi; return 0 ;;
    *.graphql|*.gql)
      echo graphql; return 0 ;;
    *.proto)
      echo protobuf; return 0 ;;
    # A JSON Schema, an Avro schema, an XML schema.
    *.schema.json|*.schema.yaml|*.schema.yml|*.avsc|*.xsd)
      echo schema; return 0 ;;
    # A FlowGoal carries interface_contracts, so editing one is a contract change.
    *.goal.yaml)
      case "$p" in
        .flow/goals/*|*/.flow/goals/*) echo goal-contract; return 0 ;;
      esac
      ;;
  esac

  # Directory-shaped patterns: a migration is a migration because of where it
  # lives, not what it is called. `migrations_helper.go` is not one.
  case "/$p" in
    */migrations/*|*/migrate/*)
      case "$base" in
        *.sql|*.rb|*.py|*.js|*.ts|*.go) echo migration; return 0 ;;
      esac
      ;;
  esac
  case "/$p" in
    */openapi/*|*/swagger/*)
      case "$base" in
        *.yaml|*.yml|*.json) echo openapi; return 0 ;;
      esac
      ;;
  esac

  return 1
}

emit() {
  local p="$1" k
  [ -n "$p" ] || return 0
  if k=$(kind_of "$p"); then
    printf 'CONTRACT_FILE=%s|%s\n' "$p" "$k"
    FOUND=1
  fi
}

FOUND=0

if [ "$#" -gt 0 ]; then
  for arg in "$@"; do
    emit "$arg"
  done
else
  while IFS= read -r line; do
    emit "$line"
  done
fi

[ "$FOUND" = 1 ]
