#!/bin/sh
set -eu
set -f

export PAGER=cat

fail() {
  echo "readonly-broker: $*" >&2
  exit 1
}

is_safe_token() {
  case "$1" in
    "") return 1 ;;
    *[\;\|\&\>\<\`\$\(\)\{\}\[\]\\\"\']* ) return 1 ;;
    * ) return 0 ;;
  esac
}

is_safe_path() {
  case "$1" in
    /var/log/*|/etc/*|/opt/*|/srv/*) return 0 ;;
    *) return 1 ;;
  esac
}

validate_run_args() {
  cmd="$1"
  shift

  case "$cmd" in
    journalctl)
      ;;
    systemctl)
      [ "$#" -ge 1 ] || fail "systemctl requires subcommand"
      [ "$1" = "status" ] || fail "only 'systemctl status' is allowed"
      ;;
    ps|ss|df|free|uptime|uname|ls|tail|head|grep|rg)
      ;;
    cat)
      [ "$#" -ge 1 ] || fail "cat requires at least one path"
      for arg in "$@"; do
        is_safe_path "$arg" || fail "cat path not allowed: $arg"
      done
      ;;
    *)
      fail "command not allowed: $cmd"
      ;;
  esac

  for arg in "$cmd" "$@"; do
    is_safe_token "$arg" || fail "unsafe token: $arg"
  done
}

run_status() {
  echo "== hostname =="
  hostname
  echo
  echo "== uptime =="
  uptime
  echo
  echo "== memory =="
  free -h
  echo
  echo "== disk =="
  df -h
  echo
  echo "== listening ports =="
  ss -lnt
  echo
  echo "== failed systemd units =="
  systemctl --failed --no-pager --no-legend || true
}

run_logs() {
  service="$1"
  shift
  is_safe_token "$service" || fail "unsafe service name: $service"

  since="10m"
  tail="200"
  for arg in "$@"; do
    case "$arg" in
      --since=*) since="${arg#--since=}" ;;
      --tail=*) tail="${arg#--tail=}" ;;
      *) fail "unsupported logs arg: $arg" ;;
    esac
    is_safe_token "$arg" || fail "unsafe logs arg: $arg"
  done

  exec journalctl -u "$service" --since="$since" -n "$tail" --no-pager
}

ORIG="${SSH_ORIGINAL_COMMAND:-}"
[ -n "$ORIG" ] || fail "missing SSH_ORIGINAL_COMMAND"

set -- $ORIG
[ "$#" -ge 2 ] || fail "expected: opsro-broker <subcommand>"
[ "$1" = "opsro-broker" ] || fail "expected opsro-broker prefix"
shift

subcommand="$1"
shift

case "$subcommand" in
  status)
    [ "$#" -eq 0 ] || fail "status takes no args"
    run_status
    ;;
  logs)
    [ "$#" -ge 1 ] || fail "logs requires a service name"
    service="$1"
    shift
    run_logs "$service" "$@"
    ;;
  run)
    [ "$#" -ge 1 ] || fail "run requires a readonly command"
    cmd="$1"
    shift
    validate_run_args "$cmd" "$@"
    exec "$cmd" "$@"
    ;;
  *)
    fail "unsupported subcommand: $subcommand"
    ;;
esac
