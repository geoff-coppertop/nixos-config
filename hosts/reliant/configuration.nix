# Phase 2 — bringing reliant's homelab stack online, migrated from defiant:
# custom.dns, custom.traefik (homelab-network), and custom.home-assistant,
# custom.mqtt, custom.matter, custom.zigbee, custom.zwave, custom.adsb
# (smart-home). Combined into a single PR since both halves target this same
# new host as one coordinated migration — see docs/provisioning.md § Two
# Phases. defiant keeps running every one of these services untouched; this
# is not a cutover. reliant is ready to activate its own instances the
# moment the Zigbee/Z-Wave USB radios are physically relocated to it.
{pkgs, ...}: let
  nas = import ../../lib/nas.nix;
  thomasga = import ../../users/thomasga/account.nix;
  # reliant's own reserved LAN IP (Unifi DHCP reservation) — distinct from
  # defiant's 192.168.20.10, which stays with defiant until the Phase 2
  # cutover step (reassigning that reservation) is done. Do NOT set this to
  # 192.168.20.10 before that cutover — both hosts would otherwise answer
  # split-horizon DNS for the same address while running independently.
  lanIp = "192.168.20.15";
in {
  imports = [
    ./secrets.nix
    ./hardware.nix
    ./power.nix
    ./disko.nix
    ./home-assistant

    ../../profiles/common
    # NOT: profiles/desktop — no display server
    # NOT: profiles/dev — no devcontainer tooling; the appliance service set
    # brought over in Phase 2 (Home Assistant, Zigbee2MQTT, Z-Wave JS, etc.)
    # doesn't need it — revisit if a future addition does.

    ../../modules
  ];

  # ── Homelab services ──────────────────────────────────────────────────────
  services = {
    # Pass-through USB serial devices for Z-Wave and Zigbee dongles — carried
    # over verbatim from hosts/defiant/configuration.nix ahead of the radios'
    # physical move. Same vendor IDs, same dialout-group target;
    # thomasga is added to "dialout" below to match.
    udev.extraRules = ''
      SUBSYSTEM=="tty", ATTRS{idVendor}=="0658", MODE="0660", GROUP="dialout"
      SUBSYSTEM=="tty", ATTRS{idVendor}=="10c4", MODE="0660", GROUP="dialout"
    '';

    # wiim: community Home Assistant integration (pkgs/home-assistant-wiim.nix)
    # for the Wiim receivers in hosts/reliant/home-assistant/sonos-wiim.nix,
    # replacing core HA's "linkplay" integration (removed from
    # custom.home-assistant.extraComponents above) -- see the comment there
    # and hosts/reliant/README.md § Known Gotchas for why. Not part of
    # nixpkgs' component-packages.nix (it's a third-party
    # custom_components/HACS package, not core), so it goes through
    # customComponents instead of extraComponents.
    home-assistant.customComponents = [
      (pkgs.callPackage ../../pkgs/home-assistant-wiim.nix {})
    ];
  };

  custom = {
    users.thomasga =
      thomasga
      // {
        groups = ["wheel" "dialout"];
        avatar = null;
      };

    home-assistant = {
      enable = true;
      # Originally mirrored hosts/defiant/configuration.nix's extraComponents
      # (defiant has since been retired) — see
      # docs/smart-home.md § Choosing extraComponents for why each of these
      # is here (mqtt and zwave_js in particular caused real outages on
      # defiant when missing). Not an exact mirror: "sonos" and "linkplay"
      # back hosts/reliant/home-assistant/sonos-wiim.nix, which targets this
      # host directly and so never shipped on defiant.
      extraComponents = [
        "homekit_controller"
        "matter"
        # sonos: HA's native Sonos integration, discovered via ssdp (already
        # listed below) — backs the Sonos S1 Amps in
        # hosts/reliant/home-assistant/sonos-wiim.nix.
        "sonos"
        # apple_tv: lets HA drive Apple TV media_player/remote entities,
        # backed by pyatv. Pairing each device's PIN (shown on-screen or in
        # the HA UI depending on protocol) is a one-time UI step; this just
        # installs the component's backend.
        "apple_tv"
        # hue: backs hosts/reliant/home-assistant/kids-wake-lights.nix's Hue
        # bulbs. Not part of HA's default_config baseline, and its config
        # flow needs the `aiohue` package the moment it actually runs (the
        # integration picker itself lists "Hue" regardless of whether this
        # is present) — see docs/smart-home.md § Choosing extraComponents.
        "hue"
        # broadlink: backs the Broadlink RM4 mini IR/RF blaster, added via
        # HA's config flow (Settings > Devices & Services > Add Integration).
        # Not part of default_config — same "config-flow-only" gap as "hue"
        # above, see docs/smart-home.md § Choosing extraComponents.
        "broadlink"
        # NOT "linkplay": core HA's linkplay integration fails to set up
        # against these Wiim Pro units specifically — confirmed live,
        # getMetaInfo returns the literal string "Failed" instead of JSON
        # (home-assistant/core#145132 and related open issues), which
        # aborts the SSDP-discovery config flow before it ever reaches the
        # UI. The community "wiim" integration
        # (services.home-assistant.customComponents, in the services block
        # above) already fixed this exact getMetaInfo handling — see
        # hosts/reliant/README.md § Known Gotchas.
        "ssdp"
        # mobile_app: required for the iOS/Android companion app to connect —
        # without it the app's error dialog reads "The mobile_app component is
        # not loaded" (Shared.HomeAssistantAPI.APIError, code 6).
        "mobile_app"
        "zwave_js"
        "mqtt"
        "conversation"
        "tts"
        "google_translate"
        "met"
        "camera"
        "image_processing"
        "assist_pipeline"
        "ai_task"
        "assist_satellite"
        "ffmpeg"
        # recorder/history: back the Climate view's "Temperature History"
        # card (hosts/reliant/home-assistant/climate-dashboard.nix). See
        # modules/home-assistant.nix's config.recorder/history YAML entries
        # for why both are needed, not just this list.
        "recorder"
        "history"
      ];
      # Same secret/value as custom.adsb.locationEnvFile below — one home
      # address, reused rather than duplicated. Keeps zone.home (and the
      # met/weather forecast derived from it) in sync with this repo's own
      # coordinates instead of whatever was typed into onboarding by hand.
      locationEnvFile = "/run/agenix/location/coordinates";
    };

    mqtt.enable = true;

    matter.enable = true;

    zigbee = {
      enable = true;
      # Same physical coordinator as defiant, once moved — confirm with
      # `ls /dev/tty{ACM,USB}*` on this host after the radio is plugged in.
      serialPort = "/dev/ttyUSB0";
      # Same network key content as defiant's — the physical Zigbee
      # coordinator carries its own network state in its NVRAM, so reusing
      # the identical key (rather than generating a new one) is what lets
      # already-paired Zigbee devices keep working without a re-pair. See
      # the PR description for the secrets-warden action this depends on
      # (adding reliant as a recipient of the existing
      # secrets/zigbee/network-key.age, not creating a new one).
      networkKeyFile = "/run/agenix/zigbee/network-key";
    };

    zwave = {
      enable = true;
      # Confirm after the controller is physically moved and plugged in:
      # ls /dev/tty{ACM,USB}*
      serialPort = "/dev/ttyACM0";
      # Same as the Zigbee key above: matched to the physical controller's
      # own NVM state, not the host, so reusing defiant's existing keys
      # (rather than generating new ones) avoids forcing an unnecessary
      # re-pair of every Z-Wave device once the controller moves.
      secretsConfigFile = "/run/agenix/zwave/secrets";
      # 3000 (the module default) collides with AdGuard Home's admin UI,
      # enabled above — same collision this host's own `defiant`
      # predecessor hit.
      port = 3001;
    };

    adsb = {
      enable = true;
      # Same physical home-address coordinates as defiant's — location data
      # isn't host- or radio-specific, so this reuses the same secret
      # content (reliant added as a recipient), not a freshly generated one.
      locationEnvFile = "/run/agenix/location/coordinates";
    };

    # Matches enterprise-d's precedent, not excelsior's (excelsior lacking
    # backups is an existing gap there, not the pattern to copy). Reuses
    # enterprise-d's job-keyed "thomasga" secrets — restic-password and
    # nas-smb-credentials are keyed to the backup job name, not the
    # machine (docs/secrets.md § Secret Inventory), and the restic repo
    # path already includes the hostname, so sharing these secrets across
    # hosts doesn't collide their backup data.
    backups = {
      enable = true;

      nas = {
        credentialsFile = "/run/agenix/thomasga/nas-smb-credentials";
        inherit (nas) host;
        share = nas.shares.backups;
      };

      # Three more backup jobs for the appliance state migrated above,
      # reusing defiant's existing job-keyed restic-password secrets (same
      # reasoning as the thomasga job's nas-smb-credentials/restic-password
      # below — job-keyed, not machine-keyed, and the repo path already
      # includes the hostname). hass/zigbee2mqtt paths confirmed live on
      # this host's first boot.
      users = {
        thomasga.enable = true;
        hass = {
          enable = true;
          paths = ["/var/lib/hass"];
          excludePatterns = ["/var/lib/hass/.storage/lovelace*" "/var/lib/hass/home-assistant_v2.db"];
        };
        zigbee2mqtt = {
          enable = true;
          paths = ["/var/lib/zigbee2mqtt"];
          excludePatterns = [];
        };
        # NOT /var/lib/zwave-js — that path never gets created. modules/zwave.nix
        # only seeds /var/lib/zwave-js via a tmpfiles rule when secretsConfigFile
        # is still the module's own default placeholder; both defiant and reliant
        # override it to an agenix path, so that rule never fires and the
        # directory has never existed on either host. zwave-js-server's real
        # network cache (device values/metadata, keyed by home ID) lives at
        # /var/cache/zwave-js instead, via systemd's CacheDirectory= — confirmed
        # live on reliant's first boot (a real ID-prefixed .jsonl/.metadata.jsonl/
        # .values.jsonl set, not an empty directory). /var/cache/zwave-js is
        # itself a symlink to private/zwave-js, same shape as this host's own
        # /var/lib/AdGuardHome symlink gotcha (see below) — restic follows a
        # symlink passed as an explicit top-level path, so this works the
        # same way that one does.
        zwave-js = {
          enable = true;
          paths = ["/var/cache/zwave-js"];
          excludePatterns = [];
        };
        # Reuses defiant's existing job-keyed restic-password secret, same
        # pattern as the three above. Capitalized — matches defiant's
        # confirmed-live path: /var/lib/AdGuardHome is a symlink to
        # private/AdGuardHome; the lowercase path doesn't exist at all
        # (case-sensitive filesystem).
        adguardhome = {
          enable = true;
          paths = ["/var/lib/AdGuardHome"];
          excludePatterns = [];
        };
      };
    };

    dns = {
      enable = true;
      domain = "coppertop.ca";
      inherit lanIp;
      # The module default (192.168.1.0/24) and this host's own VLAN
      # (192.168.20.0/24) each only cover one of the 3 LAN VLANs — widened
      # so unbound's access-control covers direct (bypass) queries on port
      # 5335 from any of them. See docs/homelab-network.md.
      lanSubnet = "192.168.0.0/16";
      # Matches defiant's full subdomain list: home-assistant, adsb, and
      # zigbee (Zigbee2MQTT) all self-register their own Traefik routes when
      # their custom.* modules are enabled (see modules/home-assistant.nix,
      # modules/adsb.nix, modules/zigbee.nix), which they now are, above.
      # dns1 is this host's own AdGuard admin UI; dns2 and dcs are the
      # cross-host routers to excelsior's AdGuard admin UI and DCS
      # on-demand control page, defined by hand below.
      subdomains = ["home" "dns1" "dns2" "dcs" "adsb" "zigbee"];
      # Renamed from the module default "dns", carried from defiant — dns1
      # (this host) and dns2 (excelsior) pair the two AdGuard instances.
      adminSubdomain = "dns1";
    };

    traefik = {
      enable = true;
      acme = {
        email = "geoff.coppertop@gmail.com";
        dnsProvider = "cloudflare";
        # Reused from defiant's existing secret — just an API credential,
        # not tied to either host's identity, so no reason to mint a
        # second one. See hosts/reliant/secrets.nix.
        environmentFile = "/run/agenix/traefik/cloudflare-api-token";
        domain = "coppertop.ca";
      };
    };
  };

  # dns2: excelsior runs its own independent unbound+AdGuard instance;
  # Traefik only runs on this host (mirroring defiant's setup, carried over
  # so reliant can be the only Traefik instance once defiant retires).
  # modules/dns.nix's self-registration only ever points at 127.0.0.1, so
  # excelsior's admin UI needs a route defined manually, cross-host. Merges
  # fine alongside the module-contributed routes since dynamicConfigOptions
  # is a freeform TOML type. See docs/homelab-network.md § Second DNS
  # Instance (excelsior).
  #
  # dcs.coppertop.ca: excelsior's on-demand DCS start/stop control page +
  # webhook (custom.dcsServer.control), cross-host and firewall-restricted
  # to this host the same way as dns2 above, no Traefik auth yet.
  # Starting/stopping a live session is a bigger blast radius than the
  # read-only AdGuard panel, so this genuinely wants real auth sooner
  # rather than later, but that's being done holistically across all these
  # routers rather than one at a time — deliberately not added here yet.
  #
  # This used to also carry a same-origin reverse proxy for DCS's own
  # remote-control WebGUI (custom.dcsServer.webGuiProxy) — removed.
  # Confirmed live (and confirmed via DCS's own forum/community docs): DCS
  # deliberately rejects WebGUI API calls that don't arrive from a
  # genuinely local connection, by design, specifically to prevent this
  # exact reverse-proxy pattern — no combination of loopback binding,
  # credentials mode, or Host header tried here got past it. DCS's real
  # remote-control mechanism assumes ports 8088 (WebGUI) and 10308 (game)
  # are directly port-forwarded from the WAN to excelsior, reachable
  # without any HTTP-layer proxy in the path at all — see
  # hosts/excelsior/configuration.nix and hosts/excelsior/README.md Known
  # Gotchas. dcs.coppertop.ca is now just the control page/webhook.
  # Both routers below need explicit priorities: dcsControlPage's rule
  # ("Host(...)") is a substring of dcsControlHooks's rule
  # ("Host(...) && PathPrefix(/hooks)"), and Traefik's default
  # rule-length-based priority for the unprefixed page router beat a
  # previous hardcoded priority on the hooks router alone, silently
  # routing /hooks/* to nginx (a raw 404) instead of the webhook.
  services.traefik.dynamicConfigOptions.http = {
    routers = {
      dns2 = {
        rule = "Host(`dns2.coppertop.ca`)";
        service = "dns2";
        tls = {};
      };

      dcsControlHooks = {
        rule = "Host(`dcs.coppertop.ca`) && PathPrefix(`/hooks`)";
        service = "dcsControlHooks";
        priority = 100;
        tls = {};
      };

      dcsControlPage = {
        rule = "Host(`dcs.coppertop.ca`)";
        service = "dcsControlPage";
        priority = 1;
        tls = {};
      };
    };

    services = {
      dns2.loadBalancer.servers = [{url = "http://192.168.1.10:3000";}];
      dcsControlHooks.loadBalancer.servers = [{url = "http://192.168.1.10:9091";}];
      dcsControlPage.loadBalancer.servers = [{url = "http://192.168.1.10:9090";}];
    };
  };

  # Headless — the only way in is SSH with an authorized key
  # (modules/users.nix's authorizedKeysFor), never a physical console.
  # That key check is the actual gate; a sudo password on top of it just
  # blocks unattended remote deploys (nixos-rebuild --target-host) without
  # adding real security.
  security.sudo.wheelNeedsPassword = false;

  services.openssh = {
    enable = true;
    openFirewall = true;

    settings = {
      KbdInteractiveAuthentication = false;
      PasswordAuthentication = false;
      PermitRootLogin = "no";
    };
  };

  # ── Networking ────────────────────────────────────────────────────────────
  networking = {
    # Reserved LAN IP: 192.168.20.15, set as a DHCP reservation in Unifi —
    # distinct from defiant's own reservation (192.168.20.10, staying with
    # defiant until the final cutover). Consumed by custom.dns.lanIp above
    # (via the `lanIp` let-binding) now that Phase 2 has wired the homelab
    # stack over.
    hostName = "reliant";

    # Confirmed live: this host's own custom.backups.nas mount fails without
    # it ("mount error: could not resolve address for unas-pro: Unknown
    # error") — the NAS hostname isn't mDNS-resolvable here, it's a static
    # /etc/hosts alias every host with a NAS mount needs, matching
    # hosts/defiant/configuration.nix and hosts/enterprise-d/configuration.nix.
    hosts.${nas.ip} = [nas.host];

    # Home Assistant's Sonos integration subscribes each speaker directly to
    # HA's own HTTP server (port 8123) for UPnP event callbacks -- LAN-local
    # traffic that never goes through Traefik, so modules/home-assistant.nix
    # deliberately doesn't open 8123 itself (everything else reaches HA only
    # via Traefik -> 127.0.0.1 — see modules/home-assistant.nix for why
    # there's no `openFirewall` there any more), which leaves the Sonos
    # callback path unreachable without this rule. Confirmed live on defiant
    #
    # unbound (modules/dns.nix) has its own access-control option to scope
    # its LAN-bypass port to a subnet; HA's http integration has no
    # equivalent allowlist for its main listener, so the restriction has to
    # happen at the firewall instead of blanket-opening 8123 via
    # allowedTCPPorts. 192.168.20.0/24 is the same homelab VLAN defiant used
    # (this host and defiant share it) -- narrower than custom.dns.lanSubnet's
    # widened 192.168.0.0/16 above, since Sonos doesn't need cross-VLAN reach
    # the way the DNS bypass does.
    firewall.extraCommands = ''
      iptables -I nixos-fw -p tcp -s 192.168.20.0/24 --dport 8123 -j ACCEPT
    '';
  };

  # Per-host override of the shared default (10, profiles/common/base.nix) —
  # the 120GB mSATA disk has far less headroom than enterprise-d/excelsior's
  # NVMe/SSDs, and this host's own `defiant` predecessor's SD card already
  # showed what an unbounded (or too-high) generation count does to a
  # small, fixed disk. Kept in sync with hardware.nix's
  # boot.loader.systemd-boot.configurationLimit (also 5). Revisit both once
  # real disk usage is known.
  custom.nix.gc.keepGenerations = 5;

  system.stateVersion = "25.11";
}
