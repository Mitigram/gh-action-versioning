#!/bin/sh

set -eu

# Set this to 1 for more verbosity (on stderr)
SEMVER_VERBOSE=${SEMVER_VERBOSE:-0}

# When this is non-empty, it will contain the label to use for all semver
# pre-releases. The default is to have it empty, meaning that the label will be
# meaningfullt picked from the git branch name.
SEMVER_PRERELEASE=${SEMVER_PRERELEASE:-}

# When this is non-empty, a series of environment variables led by this prefix
# (followed by an underscore) will be setup in the GitHub environment.
SEMVER_NAMESPACE=${SEMVER_NAMESPACE:-}

usage() {
  # This uses the comments behind the options to show the help. Not extremly
  # correct, but effective and simple.
  echo "$0 decides versions using git's tag, branch and commit information:" && \
    grep "[[:space:]].)\ #" "$0" |
    sed 's/#//' |
    sed -r 's/([a-z])\)/-\1/'
  exit "${1:-0}"
}

while getopts "p:x:vh-" opt; do
  case "$opt" in
    v) # Turn on verbosity
      SEMVER_VERBOSE=1;;
    p) # Pre-release marker to use, default to shortname of branch
      SEMVER_PRERELEASE=$OPTARG;;
    x) # Prefix to add when exporting variables (empty by default: no export)
      SEMVER_NAMESPACE=$OPTARG;;
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
    # Detect if we are part of a workflow run (we use the presence of the CI
    # variable as a marker), and either print out VAR=VALUE or a
    # GitHub-compatible function for setting output. When a namespacing prefix
    # has been set, environment variables will also be exported to the github
    # environment. Note about the CI variable: we use the CI variable as it
    # exists both in github and gitlab, making this script able to run in both
    # environments.
    if [ -z "${CI:-}" ]; then
      if [ -n "$SEMVER_NAMESPACE" ]; then
        printf "%s_%s=%s\n" "${SEMVER_NAMESPACE%%_*}" "$varname" "$value"
      else
        printf "%s=%s\n" "$varname" "$value"
      fi
    else
      # convert the name of the variable to lower case, replacing underscore
      # with dashes and print out a GitHub function for setting the output.
      id=$(printf %s\\n "$varname" | tr '[:upper:]' '[:lower:]' | sed 's/_/-/g')
      _verbose "Setting GitHub Action output $id to: $value"
      printf "::set-output name=%s::%s\n" "$id" "$value"
      # When running at github, also export an environment variable prefixed by
      # the namespacing prefix when it is non-empty.
      if [ -z "$GITHUB_ENV" ] && [ -n "$SEMVER_NAMESPACE" ]; then
        _verbose "Exporting ${SEMVER_NAMESPACE%%_*}_$varname to workflow environment"
        printf "%s_%s=%s\n" "${SEMVER_NAMESPACE%%_*}" "$varname" "$value" >> "$GITHUB_ENV"
      fi
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

# Extract which branch we are on, the nearest git tag and how far we are from it
# in terms of commits. Also extract git commit info
if [ "$#" -lt "1" ]; then
  BRANCH=$(git branch --show-current)
  _fromtag
elif printf %s\\n "$1" | grep -Eq '^refs/heads/'; then
  BRANCH=$(printf %s\\n "$1" | sed -E 's~^refs/heads/~~')
  _fromtag
elif printf %s\\n "$1" | grep -Eq '^refs/tags/'; then
  TAG=$(printf %s\\n "$1" | sed -E 's~^refs/tags/~~')
  # Ask git which (remote) branches the TAG (a commit) belongs to and keep the
  # first one only.
  BRANCH=$(git branch -a -r --contains "$TAG" | head -n 1 | sed -E 's~\s*origin/~~')
  LEVEL=0
fi
COMMIT_SHA=$(git show -s --format=%H)
COMMIT_SHORT_SHA=$(git show -s --format=%h)

# The short name for the branch is everything after the last "slash", this
# facilitate giving good pre-release version names when being on feature or user
# branches, e.g. feature/my-feature or users/emmanuel/my-feature.
BRANCH_SHORTNAME=$(printf %s\\n "$BRANCH" | sed 's~/~\n~g' | tail -n 1)

# Extract something that would look like major.minor.patch from the tag (which
# allows to have tags with v1.2.3 for example), being laxist around minor and
# patch. Then extract the major, minor and patch values (defaulting to zeroes)
VERSION=$(printf %s\\n "$TAG" | grep -Eo '[0-9]+(\.[0-9]+(\.[0-9]+)?)?')
MAJOR=$(printf %s.0.0\\n "$VERSION" | grep -Eo '[0-9]+\.[0-9]+\.[0-9]' | sed -E 's/([0-9]+)\.([0-9]+)\.([0-9]+)/\1/')
MINOR=$(printf %s.0.0\\n "$VERSION" | grep -Eo '[0-9]+\.[0-9]+\.[0-9]' | sed -E 's/([0-9]+)\.([0-9]+)\.([0-9]+)/\2/')
PATCH=$(printf %s.0.0\\n "$VERSION" | grep -Eo '[0-9]+\.[0-9]+\.[0-9]' | sed -E 's/([0-9]+)\.([0-9]+)\.([0-9]+)/\3/')

# Next semantic version will have an increase on patch number
NEXT=$(( PATCH + 1 ))

# Generate a semantic version number that tells us where we are: When exactly at
# a tag, this will be the exact version contained in the tag, without any
# leading v. Otherwise, the semantic version has a patch number +1:ed from the
# one contained in the nearest tag (as this is what we are heading to) and uses
# the pre-release part of the semver spect to express the feature we are working
# on, and how far we are from the tag. The name of the feature, coming from the
# branch name, is only used by default, permitting callers to provide a specific
# prerelease marker through the command-line, e.g. "preview".
if [ "$LEVEL" = "0" ]; then
  SEMVER="${MAJOR}.${MINOR}.${PATCH}"
elif [ -z "$SEMVER_PRERELEASE" ]; then
  SEMVER="${MAJOR}.${MINOR}.${NEXT}-${BRANCH_SHORTNAME}.${LEVEL}"
else
  SEMVER="${MAJOR}.${MINOR}.${NEXT}-${SEMVER_PRERELEASE}.${LEVEL}"
fi

_export SEMVER VERSION TAG BRANCH BRANCH_SHORTNAME COMMIT_SHA COMMIT_SHORT_SHA