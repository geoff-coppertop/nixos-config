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

        # Headless host, no hibernation: modest swap, no LVM (no LUKS to layer).
        swap = {
          size = "8G";
          content = {type = "swap";};
        };

        root = {
          size = "100%";

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

              # DCS install + wine prefix (~60-120 GB). Own subvolume keeps it
              # out of snapper's / and /home timeline snapshots.
              "@dcs" = {
                mountpoint = "/var/lib/dcs-server";
                mountOptions = ["compress=zstd" "noatime"];
              };
            };
          };
        };
      };
    };
  };
}
