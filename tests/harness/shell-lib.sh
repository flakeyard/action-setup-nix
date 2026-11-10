# shellcheck shell=bash disable=SC2154,SC2034 # shared with tests/harness
# action-shell-lib at the commit that action.yml pins, whose env.sh and
# run-step.sh the steps use. CI gives it in SHELL_LIB; otherwise it is fetched
# once into the cache. The steps get a copy whose SYSTEM_PATH is the tools of
# the tests. Sourced by tests/run.sh after env.sh.

LIBRARY_URL=https://github.com/flakeyard/action-shell-lib
# The pin in action.yml; the commit is the first group.
LIBRARY_PIN_RE='uses: flakeyard/action-shell-lib@([0-9a-f]{40})'

# pinned_library_commit: prints the commit of the library that action.yml
# pins; exits if it pins none.
pinned_library_commit() {
  local line
  while IFS= read -r line; do
    if [[ $line =~ $LIBRARY_PIN_RE ]]; then
      echo "${BASH_REMATCH[1]}"
      return 0
    fi
  done <"$root/action.yml"
  echo "tests/run.sh: action.yml pins no action-shell-lib" >&2
  exit 2
}

# clone_commit COMMIT DIR: only COMMIT of the library, checked out in DIR.
clone_commit() {
  local commit=$1 dir=$2
  git -C "$dir" init --quiet &&
    git -C "$dir" fetch --quiet --depth 1 "$LIBRARY_URL" "$commit" &&
    git -C "$dir" -c advice.detachedHead=false checkout --quiet FETCH_HEAD
}

# fetch_library COMMIT DIR: the library at COMMIT in DIR, unless DIR exists.
fetch_library() {
  local commit=$1 dir=$2 temp
  [[ ! -d $dir ]] || return 0
  mkdir -p -- "${dir%/*}"
  temp=$(mktemp -d "$dir.XXXXXX")
  if ! clone_commit "$commit" "$temp" || ! mv -T -- "$temp" "$dir"; then
    rm -rf -- "$temp"
    echo "tests/run.sh: cannot fetch $LIBRARY_URL at $commit" >&2
    exit 2
  fi
}

# resolve_library: library, the directory of the library: SHELL_LIB, or the
# pinned commit in the cache.
resolve_library() {
  local commit
  if [[ -n ${SHELL_LIB-} ]]; then
    library=$SHELL_LIB
    return 0
  fi
  commit=$(pinned_library_commit) || exit 2
  library=${XDG_CACHE_HOME:-$HOME/.cache}/flakeyard/action-shell-lib/$commit
  fetch_library "$commit" "$library"
}

# copy_library: $shell_lib, a copy of the library whose SYSTEM_PATH is the
# tools of the tests; exits if env.sh of the library no longer has it.
copy_library() {
  local env_sh=$shared/shell-lib/env.sh system_path=$root/tests/harness/stub:$sysbin
  shell_lib=$shared/shell-lib
  cp -R -- "$library" "$shell_lib"
  sed -i -e "s|^readonly SYSTEM_PATH=.*|readonly SYSTEM_PATH=$system_path|" "$env_sh"
  # Without it, the scripts would run the tools of the host.
  if ! grep -qx "readonly SYSTEM_PATH=$system_path" "$env_sh"; then
    echo "tests/run.sh: cannot redirect SYSTEM_PATH in env.sh of the library" >&2
    exit 2
  fi
}

resolve_library
copy_library
