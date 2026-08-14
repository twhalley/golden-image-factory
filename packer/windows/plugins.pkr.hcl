// Plugin pins for the Windows templates.
//
// Duplicated from packer/linux/plugins.pkr.hcl rather than shared, because
// Packer resolves required_plugins per template directory and there is no
// include mechanism. Keep the two in step — CI validates both, so a divergence
// shows up as a version mismatch rather than silently.
//
// No azure plugin here: the Windows Azure build is phase 8 and starts from a
// marketplace base image, so declaring the dependency now would be declaring one
// that nothing uses.
packer {
  required_version = ">= 1.12.0"

  required_plugins {
    qemu = {
      source  = "github.com/hashicorp/qemu"
      version = "~> 1.1"
    }
    vmware = {
      source  = "github.com/hashicorp/vmware"
      version = "~> 2.1"
    }
    vsphere = {
      source  = "github.com/hashicorp/vsphere"
      version = "~> 2.3"
    }
    ansible = {
      source  = "github.com/hashicorp/ansible"
      version = "~> 1.1"
    }
  }
}
