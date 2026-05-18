{
  disko.devices = {
    disk.main = {
      type = "disk";

      # Provided by the installer script
      device = builtins.getEnv "DISKO_DEVICE";

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

              mountOptions = [
                "umask=0077"
              ];
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
                  "@" = {
                    mountpoint = "/";
                  };

                  "@home" = {
                    mountpoint = "/home";
                  };
                };
              };
            };
          };
        };
      };
    };
  };
}
