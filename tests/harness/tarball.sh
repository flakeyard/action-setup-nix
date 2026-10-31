# shellcheck shell=bash disable=SC2154,SC2034 # shared with tests/harness
# Fake Nix release tarballs, served by the curl stub. Sourced by tests/run.sh.

# tarball_fixture VERSION SYSTEM: prints the path of a release tarball that the
# curl stub serves.
tarball_fixture() {
  local version=$1 system=$2
  echo "$work/fixtures/nix-$version-$system.tar.xz"
}

# sha256_of FILE: prints the SHA-256 of FILE.
sha256_of() {
  sha256sum <"$1" | cut -d' ' -f1
}

# pin_tarball VERSION SYSTEM: pins the hash of the release tarball of SYSTEM
# in the copy of the action.
pin_tarball() {
  local version=$1 system=$2 var=NIX_SHA256_${2//-/_} hash
  hash=$(sha256_of "$(tarball_fixture "$version" "$system")")
  sed -i -e "s|^$var=.*|$var=$hash|" "$action/versions.sh"
}

# repack_tarball VERSION SYSTEM: packs $work/tarball/nix-VERSION-SYSTEM again
# into the release tarball, after a change.
repack_tarball() {
  local version=$1 system=$2
  tar --create --xz --file "$(tarball_fixture "$version" "$system")" \
    --directory "$work/tarball" "nix-$version-$system"
}

# fake_tarball VERSION SYSTEM [NIX_VERSION_OUTPUT]: a release tarball whose
# installer records its arguments and environment, writes nix.conf like the
# real one and installs a stub of nix.
fake_tarball() {
  local version=$1 system=$2 reported=${3:-$1}
  local dir=$work/tarball/nix-$version-$system
  mkdir -p "$dir"
  cat >"$dir/install" <<EOF
#!/bin/bash
echo "install \$*" >>"$work/calls"
env >"$work/installer-env"
while ((\$#)); do
  [[ \$1 == --nix-extra-conf-file ]] && conf=\$2
  shift
done
mkdir -p "$fs/etc/nix" "$fs/nix/var/nix/profiles/default/bin"
{ cat "\$conf"; echo "build-users-group = nixbld"; } >"$fs/etc/nix/nix.conf"
cat >"$fs/nix/var/nix/profiles/default/bin/nix" <<'NIX'
#!/bin/bash
case "\$*" in
  --version) echo "nix (Nix) $reported" ;;
  "store info") [[ ! -e "$work/daemon-down" ]] ;;
  "config show "*) sed -n "s/^\$3 = //p" "$fs/etc/nix/nix.conf" ;;
  *) exit 1 ;;
esac
NIX
chmod +x "$fs/nix/var/nix/profiles/default/bin/nix"
EOF
  chmod +x "$dir/install"
  repack_tarball "$version" "$system"
}
