# Plain GPT layout: ESP + swap + ext4 root, no LUKS/TPM (no TPM2 confirmed
# on this hardware — do not adopt enterprise-d's LUKS+TPM pattern here
# without first confirming a TPM2 chip is actually present) and no LVM.
#
# ext4, not excelsior's btrfs-with-subvolumes: excelsior's `@`/`@home`/`@dcs`
# split exists to keep a large, fast-growing DCS install (60-120GB on its
# own) out of snapper's timeline snapshots on a 1TB disk with headroom to
# spare. This disk is 120GB total — smaller than excelsior's DCS install
# alone — and this host's homelab state (Home Assistant recorder DB,
# Zigbee2MQTT, Z-Wave JS, AdGuard, growing over time) is expected to keep
# growing on it. Adding btrfs CoW + snapper timeline snapshots on top of
# that, on a disk this small, is exactly the kind of disk-pressure risk
# `defiant` (this host's retired predecessor) hit on its fixed-size SD
# card — snapshots would compete with live service state for space no
# NVMe/SSD host in this repo has had to worry about. Plain ext4 avoids that
# risk entirely; btrfs + snapper can be added later if it turns out there's
# headroom to spare.
{disks ? ["/dev/sda"], ...}: {
  disko.devices.disk.main = {
    type = "disk";
    device = builtins.elemAt disks 0;

    content = {
      type = "gpt";

      partitions = {
        ESP = {
          size = "1G";
          type = "EF00";

          content = {
            type = "filesystem";
            format = "vfat";
            mountpoint = "/boot";
            mountOptions = ["umask=0077"];
          };
        };

        # Headless host, no hibernation: modest swap. 4G, not excelsior's 8G
        # — half this host's 8GB RAM is already generous for a server that
        # never hibernates, and every GB here is a GB not available to root
        # on a 120GB disk.
        swap = {
          size = "4G";
          content = {type = "swap";};
        };

        root = {
          size = "100%";

          content = {
            type = "filesystem";
            format = "ext4";
            mountpoint = "/";
          };
        };
      };
    };
  };
}
