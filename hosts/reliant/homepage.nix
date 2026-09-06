_: {
  # Landing page at https://coppertop.ca linking to the fleet's services.
  # Runs on reliant (the hub); the apex DNS record and cert are wired in
  # configuration.nix and the traefik module.
  #
  # The ARM and tinyMediaManager links point at excelsior via this host's
  # cross-host Traefik routes and only resolve once that work (a separate
  # PR) is also deployed.
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
              href = "https://rip.coppertop.ca";
              description = "Disc rip queue";
            };
          }
          {
            "tinyMediaManager" = {
              href = "https://library.coppertop.ca";
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
          {
            "Zigbee2MQTT" = {
              href = "https://zigbee.coppertop.ca";
              description = "Zigbee devices";
              icon = "zigbee2mqtt";
            };
          }
        ];
      }
      {
        "Games" = [
          {
            "DCS World Control" = {
              href = "https://dcs.coppertop.ca";
              description = "Start/stop the dedicated server";
            };
          }
        ];
      }
      {
        "Network" = [
          {
            "AdGuard (dns1)" = {
              href = "https://dns1.coppertop.ca";
              description = "reliant resolver";
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
        ];
      }
      {
        "Monitoring" = [
          {
            "ADS-B" = {
              href = "https://adsb.coppertop.ca";
              description = "Flight tracking";
            };
          }
        ];
      }
    ];
  };
}
