{disks ? ["/dev/nvme0n1" "/dev/nvme1n1"], ...}: {
  disko.devices = {
    disk = {
      # Disk 1 (512 GB): NixOS root + home. LUKS → LVM → swap + btrfs.
      main = {
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

            root = {
              size = "100%";

              content = {
                type = "luks";
                name = "root";
                passwordFile = "/tmp/encryption-password";

                settings = {
                  allowDiscards = true;
                };

                content = {
                  type = "lvm_pv";
                  vg = "vg";
                };
              };
            };
          };
        };
      };

      # Disk 2 (2 TB): game library. LUKS → btrfs, mounted at /games. Formatted
      # with the same passphrase as root at install (the installer only prompts
      # once). Unlocked in stage-2, not initrd (initrdUnlock = false), so it
      # never blocks boot; TPM-enrol it post-install exactly like root and it
      # auto-unlocks with no prompt. See README.
      games = {
        type = "disk";
        device = builtins.elemAt disks 1;

        content = {
          type = "gpt";

          partitions.games = {
            size = "100%";

            content = {
              type = "luks";
              name = "games";
              initrdUnlock = false;
              passwordFile = "/tmp/encryption-password";

              settings = {
                allowDiscards = true;
              };

              content = {
                type = "btrfs";
                extraArgs = ["-L" "games"];

                subvolumes."@games" = {
                  mountpoint = "/games";
                  mountOptions = ["compress=zstd" "noatime"];
                };
              };
            };
          };
        };
      };
    };

    lvm_vg.vg = {
      type = "lvm_vg";

      lvs = {
        # No hibernation on this desktop (64 GB RAM), so swap is modest and
        # there is no resumeDevice — unlike enterprise-d's RAM-sized swap.
        swap = {
          size = "16G";
          content = {
            type = "swap";
          };
        };

        root = {
          size = "100%FREE";
          content = {
            type = "btrfs";
            extraArgs = ["-L" "root"];

            subvolumes = {
              "@" = {
                mountpoint = "/";
                mountOptions = ["compress=zstd" "noatime"];
              };

              "@home" = {
                mountpoint = "/home";
                mountOptions = ["compress=zstd" "noatime"];
              };
            };
          };
        };
      };
    };
  };
}
