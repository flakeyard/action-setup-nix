# shellcheck shell=bash disable=SC2154,SC2034 # shared with tests/harness
# Unit tests of scripts/step/install.sh.

setup_action
run "install: installs the pinned tarball" ok step/install.sh \
  NIX_USER_COUNT=1 NIX_CONFIG="sandbox = false" NIX_VERSION=9.9.9 \
  NIX_BASE_URL=https://evil.test
expect call "curl https://example.test/nix/nix-${NIX_VERSION}/nix-${NIX_VERSION}-x86_64-linux.tar.xz"
expect call "install --daemon --yes --no-channel-add --nix-extra-conf-file"
expect_path "${fs}/nix/var/nix/profiles/default/bin"
if [[ -n ${current} ]] && leaked=$(grep -E '^(NIX_|CALLS|FIXTURES|GITHUB_)' "${work}/installer-env"); then
  report "the installer got the job environment: ${leaked}"
fi
conf=$(SHELL_LIB="${shell_lib}" "${action}/scripts/lib/nix-conf.sh")
expect_file "${fs}/etc/nix/nix.conf" "${conf}"$'\n'"build-users-group = nixbld"
if [[ -n ${current} ]] && left=$(ls -A "${work}/temp") && [[ -n ${left} ]]; then
  report "temporary files left: ${left}"
fi
finish

setup_action
fake_tarball "${NIX_VERSION}" aarch64-linux
pin_tarball "${NIX_VERSION}" aarch64-linux
run "install: arm64 tarball" ok step/install.sh RUNNER_ARCH=ARM64
expect call "curl https://example.test/nix/nix-${NIX_VERSION}/nix-${NIX_VERSION}-aarch64-linux.tar.xz"
finish

setup_action
fixture=$(tarball_fixture "${NIX_VERSION}" x86_64-linux)
echo tampered >>"${fixture}"
run "install: hash mismatch installs nothing" fail step/install.sh
expect message "::error::SHA-256 of https://example.test/nix/nix-${NIX_VERSION}/nix-${NIX_VERSION}-x86_64-linux.tar.xz is"
expect no-call "install --daemon"
[[ -z ${current} || ! -e ${fs}/etc/nix ]] || report "nix.conf was written"
finish

setup_action
fixture=$(tarball_fixture "${NIX_VERSION}" x86_64-linux)
rm "${fixture}"
run "install: download failure" fail step/install.sh
expect no-call "install --daemon"
finish

setup_action
run "install: extra caches reach nix.conf" ok step/install.sh \
  SUBSTITUTERS="https://cache.example.org" KEYS="${key}"
conf=$(SHELL_LIB="${shell_lib}" SUBSTITUTERS="https://cache.example.org" KEYS="${key}" "${action}/scripts/lib/nix-conf.sh")
expect_file "${fs}/etc/nix/nix.conf" "${conf}"$'\n'"build-users-group = nixbld"
finish

setup_action
sed -i 's|^#!/bin/bash$|#!/bin/bash\nexit 3|' "${work}/tarball/nix-${NIX_VERSION}-x86_64-linux/install"
repack_tarball "${NIX_VERSION}" x86_64-linux
pin_tarball "${NIX_VERSION}" x86_64-linux
run "install: installer failure" fail step/install.sh
expect message "::error::The Nix installer failed"
[[ -z ${current} || ! -s ${work}/path ]] || report "PATH was extended: $(<"${work}/path")"
if [[ -n ${current} ]] && left=$(ls -A "${work}/temp") && [[ -n ${left} ]]; then
  report "temporary files left"
fi
finish

setup_action
run_with_job_path "install: no tools of the job PATH and no code of its environment" install
expect_path "${fs}/nix/var/nix/profiles/default/bin"
finish
