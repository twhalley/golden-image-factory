// Plugin pins. These moved out of Packer core in 1.7 and the source addresses
// changed again when HashiCorp reorganised the plugin repositories, so the
// addresses below were verified against the current releases rather than copied
// from an older template. Bump deliberately; `packer init -upgrade` will not
// respect the intent of a `~>` constraint across a major version.
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
    azure = {
      source  = "github.com/hashicorp/azure"
      version = "~> 2.6"
    }
    ansible = {
      source  = "github.com/hashicorp/ansible"
      version = "~> 1.1"
    }
  }
}
