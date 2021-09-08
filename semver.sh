#!/bin/sh

set -eu

SEMVER_VERBOSE=${SEMVER_VERBOSE:-0}
SEMVER_PRERELEASE=${SEMVER_PRERELEASE:-}

usage() {
  # This uses the comments behind the options to show the help. Not extremly
  # correct, but effective and simple.
  echo "$0 decides versions using git's tag, branch and commit information:" && \
    grep "[[:space:]].)\ #" "$0" |
    sed 's/#//' |
    sed -r 's/([a-z])\)/-\1/'
  exit "${1:-0}"
}

while getopts "p:vh-" opt; do
  case "$opt" in
    v) # Turn on verbosity
      SEMVER_VERBOSE=1;;
    p) # Pre-release marker to use, default to shortname of branch
      SEMVER_PRERELEASE=$OPTARG;;
    h) # Print help and exit
      usage;;
    -)
      break;;
    *)
      usage 1;;
  esac
done
shift $((OPTIND-1))


_verbose() {
  if [ "$SEMVER_VERBOSE" = "1" ]; then
    printf %s\\n "$1" >&2
  fi
}

_error() {
  printf %s\\n "$1" >&2
  exit 1
}

_export() {
  # shellcheck disable=SC3043 # local is implemented in almost all shells
  local varname value id

  for varname in "$@"; do
    value=$(set | grep -E "^${varname}=" | sed -E "s/^${varname}='([^']+)'/\1/")
    if [ -z "${GITHUB_ENV:-}" ]; then
      printf "%s=%s\n" "$varname" "$value"
    else
      id=$(printf %s\\n "$varname" | tr '[:upper:]' '[:lower:]' | sed 's/_/-/g')
      _verbose "Setting GitHub Action output $id to: $value"
      printf "::set-output name=%s::%s\n" "$id" "$value"
    fi
  done
}

_fromtag() {
  if git describe --tags >/dev/null 2>&1; then
    levelled_version=$(git describe --tags --abbrev=7 |
                        rev |
                        cut -c 10- |
                        rev || true)
    LEVEL=$(printf %s\\n "$levelled_version" | grep -Eo -e '-[0-9]+$' | sed -E 's/^-//')
    TAG=$(printf %s\\n "$levelled_version" | sed -E 's/-[0-9]+$//')
  else
    LEVEL=0
    TAG=0.0.0
  fi
}

if [ "$#" -lt "1" ]; then
  GIT_BRANCH=$(git branch --show-current)
  _fromtag
elif printf %s\\n "$1" | grep -Eq '^refs/heads/'; then
  GIT_BRANCH=$(printf %s\\n "$1" | sed -E 's~^refs/heads/~~')
  _fromtag
elif printf %s\\n "$1" | grep -Eq '^refs/tags/'; then
  TAG=$(printf %s\\n "$1" | sed -E 's~^refs/tags/~~')
  # Ask git which (remote) branches the TAG (a commit) belongs to and keep the
  # first one only.
  GIT_BRANCH=$(git branch -a -r --contains "$TAG" | head -n 1 | sed -E 's~\s*origin/~~')
  LEVEL=0
fi

GIT_BRANCH_SHORTNAME=$(printf %s\\n "$GIT_BRANCH" | sed 's~/~\n~g' | tail -n 1)
VERSION=$(printf %s\\n "$TAG" | grep -Eo '[0-9+]\.[0-9+]\.[0-9+]')

if [ "$LEVEL" = "0" ]; then
  SEMVER="$VERSION"
elif [ -z "$SEMVER_PRERELEASE" ]; then
  SEMVER="${VERSION}-${GIT_BRANCH_SHORTNAME}.${LEVEL}"
else
  SEMVER="${VERSION}-${SEMVER_PRERELEASE}.${LEVEL}"
fi

_export SEMVER VERSION TAG GIT_BRANCH GIT_BRANCH_SHORTNAME