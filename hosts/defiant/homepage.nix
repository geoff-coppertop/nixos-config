_: {
  # Landing page at https://coppertop.ca linking to the fleet's services.
  # Runs on defiant (the hub); the apex DNS record and cert are wired in
  # configuration.nix and the traefik module.
  custom.homepage.enable = true;

  services.homepage-dashboard = {
    settings = {
      title = "coppertop.ca";
      headerStyle = "clean";
    };

    services = [
      {
        "Media" = [
          {
            "Jellyfin" = {
              href = "https://jellyfin.coppertop.ca";
              description = "Movies, shows, and music";
              icon = "jellyfin";
            };
          }
          {
            "Ripping (ARM)" = {
              href = "https://arm.coppertop.ca";
              description = "Disc rip queue";
            };
          }
          {
            "tinyMediaManager" = {
              href = "https://tmm.coppertop.ca";
              description = "Library metadata";
            };
          }
        ];
      }
      {
        "Home" = [
          {
            "Home Assistant" = {
              href = "https://home.coppertop.ca";
              description = "Automations and devices";
              icon = "home-assistant";
            };
          }
        ];
      }
      {
        "Network" = [
          {
            "AdGuard (dns1)" = {
              href = "https://dns1.coppertop.ca";
              description = "defiant resolver";
              icon = "adguard-home";
            };
          }
          {
            "AdGuard (dns2)" = {
              href = "https://dns2.coppertop.ca";
              description = "excelsior resolver";
              icon = "adguard-home";
            };
          }
          {
            "ADS-B" = {
              href = "https://adsb.coppertop.ca";
              description = "Flight tracking";
            };
          }
          {
            "Zigbee2MQTT" = {
              href = "https://zigbee.coppertop.ca";
              description = "Zigbee devices";
              icon = "zigbee2mqtt";
            };
          }
        ];
      }
    ];
  };
}
