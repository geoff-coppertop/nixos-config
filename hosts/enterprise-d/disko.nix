{disks ? ["/dev/nvme0n1"], ...}: {
  disko.devices = {
    disk.main = {
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
                # Discards leak block usage metadata through the LUKS layer.
                # Disable if that's a concern; enable for SSD longevity.
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

    lvm_vg.vg = {
      type = "lvm_vg";

      lvs = {
        # Size should match physical RAM for full hibernation support
        swap = {
          size = "32G";
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
