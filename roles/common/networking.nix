{config, ...}: {
  age.secrets = {
    "wifi/agt-home".file = ../../secrets/wifi/agt-home.age;
    "wifi/agt-iot".file = ../../secrets/wifi/agt-iot.age;
    "wifi/agt-work".file = ../../secrets/wifi/agt-work.age;
  };

  networking.networkmanager = {
    enable = true;
    ensureProfiles = {
      environmentFiles = [
        config.age.secrets."wifi/agt-home".path
        config.age.secrets."wifi/agt-iot".path
        config.age.secrets."wifi/agt-work".path
      ];
      profiles = {
        "agt-home" = {
          connection = {
            id = "agt-home";
            type = "wifi";
          };
          wifi = {
            ssid = "agt-home";
            mode = "infrastructure";
          };
          wifi-security = {
            key-mgmt = "wpa-psk";
            psk = "$WIFI_AGT_HOME_PASSWORD";
          };
          ipv4.method = "auto";
          ipv6.method = "auto";
        };
        "agt-iot" = {
          connection = {
            id = "agt-iot";
            type = "wifi";
          };
          wifi = {
            ssid = "agt-iot";
            mode = "infrastructure";
          };
          wifi-security = {
            key-mgmt = "wpa-psk";
            psk = "$WIFI_AGT_IOT_PASSWORD";
          };
          ipv4.method = "auto";
          ipv6.method = "auto";
        };
        "agt-work" = {
          connection = {
            id = "agt-work";
            type = "wifi";
          };
          wifi = {
            ssid = "agt-work";
            mode = "infrastructure";
          };
          wifi-security = {
            key-mgmt = "wpa-psk";
            psk = "$WIFI_AGT_WORK_PASSWORD";
          };
          ipv4.method = "auto";
          ipv6.method = "auto";
        };
      };
    };
  };
}
