{
  disko.devices = {
    disk.main = {
      type = "disk";
      device = "/dev/nvme0n1";

      content = {
        type = "gpt";

        partitions = {
          ESP = {
            size = "512M";
            type = "EF00";
            content = {
              type = "filesystem";
              format = "vfat";
              mountpoint = "/boot/efi";
            };
          };

          boot = {
            size = "2G";
            content = {
              type = "filesystem";
              format = "ext4";
              mountpoint = "/boot";
            };
          };

          swap = {
            size = "32G";
            content = {
              type = "swap";
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
                type = "btrfs";

                subvolumes = {
                  "@" = {mountpoint = "/";};
                  "@home" = {mountpoint = "/home";};
                };
              };
            };
          };
        };
      };
    };
  };
}
