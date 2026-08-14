#!/usr/bin/env bash
#
# Generates the ephemeral SSH key pair Packer uses to reach the guest during a
# build, and prints the PKR_VAR_* exports that point at it.
#
# Why a key at all, rather than the `ssh_password` most Packer examples use:
# a password in a kickstart is a credential in the repository, and it survives
# into the image unless something explicitly removes it. This key exists for the
# life of one build, is written to a gitignored directory, and the account it
# authorises is deleted by the harden_linux role before the image is published.
#
# Usage:
#   eval "$(scripts/make-build-key.sh)"
#   packer build -only='linux.qemu.linux' -var-file=packer/linux/rocky9.pkrvars.hcl packer/linux
#
# The key is regenerated on every invocation. Nothing depends on it persisting.

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
KEY_DIR="${REPO_ROOT}/.build-keys"
KEY_PATH="${KEY_DIR}/build-$(date -u +%Y%m%dT%H%M%SZ)"

mkdir -p "${KEY_DIR}"
chmod 0700 "${KEY_DIR}"

# ed25519: small, fast, and no key-size decision to get wrong.
ssh-keygen -t ed25519 -N "" -C "golden-image-factory ephemeral build key" -f "${KEY_PATH}" >/dev/null

chmod 0600 "${KEY_PATH}"
chmod 0644 "${KEY_PATH}.pub"

# Emitted to stdout for `eval`; the human-readable note goes to stderr so it does
# not end up inside the eval.
echo "export PKR_VAR_ssh_public_key='$(cat "${KEY_PATH}.pub")'"
echo "export PKR_VAR_ssh_private_key_file='${KEY_PATH}'"

{
  echo
  echo "Ephemeral build key written to ${KEY_PATH}"
  echo "This directory is gitignored. Delete it when you are done:"
  echo "  rm -rf ${KEY_DIR}"
} >&2
