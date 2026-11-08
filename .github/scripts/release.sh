#!/bin/sh
# Helpers for release.yml, kept in a script so they run locally too.
#
#   release.sh version <head branch>   print the version of a merged release
#                                      or hotfix branch
#   release.sh notes <version>         print the CHANGELOG.md entry of that
#                                      version; print nothing if it has none
#
# The rules follow docs/agents/semver-policy.md: tag prefix `v`, versions
# `X.Y.Z` only, and a hotfix gets the next patch of the last release.
set -eu

die() {
  echo "release.sh: $*" >&2
  exit 1
}

# Highest `vX.Y.Z` tag, without the `v`; empty when there is no release.
last_release() {
  git tag --list 'v*' \
    | sed -n 's/^v\([0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\)$/\1/p' \
    | sort -t. -k1,1n -k2,2n -k3,3n \
    | tail -n 1
}

# Exit 0 when $1 is higher than $2 (both X.Y.Z).
higher() {
  [ "$1" != "$2" ] && [ "$(printf '%s\n%s\n' "$1" "$2" | sort -t. -k1,1n -k2,2n -k3,3n | tail -n 1)" = "$1" ]
}

version() {
  branch=$1
  last=$(last_release)
  case $branch in
    release/*)
      v=${branch#release/}
      echo "$v" | grep -Eq '^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$' \
        || die "branch $branch does not name a version X.Y.Z"
      # A re-run after the tag exists prints the same version again.
      if git rev-parse --verify --quiet "refs/tags/v$v" >/dev/null; then
        echo "$v"
        return
      fi
      if [ -n "$last" ] && ! higher "$v" "$last"; then
        die "version $v is not higher than the last release $last"
      fi
      echo "$v"
      ;;
    hotfix/*)
      [ -n "$last" ] || die "hotfix $branch has no release to correct"
      # A re-run after the tag exists finds the tag on the merge commit.
      on_head=$(git tag --points-at HEAD --list 'v*' | sed -n 's/^v\([0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\)$/\1/p' | head -n 1)
      if [ -n "$on_head" ]; then
        echo "$on_head"
        return
      fi
      echo "$last" | awk -F. '{ printf "%d.%d.%d\n", $1, $2, $3 + 1 }'
      ;;
    *)
      die "branch $branch is not a release/* or hotfix/* branch"
      ;;
  esac
}

# Common Changelog writes `## [X.Y.Z] - date`, or `## X.Y.Z - date` without a
# version link. The entry ends at the next `## ` heading or at the link
# definitions at the bottom of the file.
notes() {
  v=$1
  [ -f CHANGELOG.md ] || return 0
  awk -v v="$v" '
    /^## / {
      if (found) exit
      h = $0
      sub(/^## \[?/, "", h)
      sub(/\]?( .*)?$/, "", h)
      if (h == v) { found = 1; next }
    }
    found && /^\[[^]]+\]: / { exit }
    found { print }
  ' CHANGELOG.md | sed -e '/./,$!d'
}

[ $# -eq 2 ] || die "usage: release.sh version <branch> | notes <version>"
case $1 in
  version) version "$2" ;;
  notes) notes "$2" ;;
  *) die "unknown command $1" ;;
esac
