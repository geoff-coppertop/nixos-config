# Declarative Bambuddy printers and virtual printers.
#
# Separate from modules/bambuddy.nix on purpose: that file's concern is running
# the service (unit, sidecars, firewall, Traefik route), this one's is getting
# declared rows into the database it keeps. They share the custom.bambuddy
# option namespace, which the module system merges across files.
#
# Bambuddy has no seeding mechanism. Its printer list and virtual-printer
# config live in its own SQLite database under DATA_DIR, and at v1.2.5.3
# backend/app/core/config.py reads no seed file, no import path and no
# printer-related environment variables (HA_URL / HA_TOKEN are the only
# env-driven settings there). Rows are created through the web UI or the REST
# API and nowhere else, so the only route to declarative printers is to
# reconcile against that API once the service is up. That is what
# ./bambuddy-provision.py does; read its module docstring before changing
# anything here, in particular the reasons it is create-only.
{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (lib) concatMapStringsSep filter literalExpression mkIf mkOption optional types unique;
  cfg = config.custom.bambuddy;

  # Call the API on an address that actually resolves to this host:
  # listenAddress when it names one, loopback when it is a wildcard, since a
  # wildcard is a bind address and not a usable destination.
  apiAddress =
    if builtins.elem cfg.listenAddress ["0.0.0.0" "::" "*"]
    then "127.0.0.1"
    else cfg.listenAddress;
  apiHost =
    if lib.hasInfix ":" apiAddress
    then "[${apiAddress}]"
    else apiAddress;

  printerOptions = types.submodule {
    options = {
      name = mkOption {
        type = types.str;
        description = "Display name for the printer in Bambuddy (1-100 characters).";
      };

      serialNumber = mkOption {
        type = types.str;
        description = ''
          The printer's Bambu serial number (1-50 characters). This is the
          identity key: provisioning matches declared printers against
          existing ones on serial and nothing else, and Bambuddy itself
          refuses a second printer with the same serial. Bambuddy uppercases
          and trims it on input, so case here does not matter.
        '';
      };

      ipAddress = mkOption {
        type = types.str;
        description = "The printer's LAN IPv4 address or hostname.";
      };

      accessCodeFile = mkOption {
        type = types.str;
        description = ''
          Path to a file holding the printer's LAN Access Code, read at
          provisioning time — an agenix-decrypted path under /run/agenix, not
          a store path, and never the code inline. Declare the secret with no
          owner: provisioning runs as root, matching the other root-read
          secrets in hosts/<host>/secrets.nix.

          Until the file exists the printer is reported as pending and
          retried, rather than failing permanently.
        '';
        example = "/run/agenix/bambuddy/p2s-access-code";
      };

      model = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Optional printer model as Bambuddy records it, e.g. \"P2S\". Left unset Bambuddy detects it over MQTT.";
      };

      location = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Optional group/location label used to organise printers in the UI.";
      };

      autoArchive = mkOption {
        type = types.bool;
        default = true;
        description = "Archive finished prints from this printer automatically. Matches Bambuddy's own default.";
      };
    };
  };

  virtualPrinterOptions = types.submodule {
    options = {
      name = mkOption {
        type = types.str;
        description = ''
          Name of the virtual printer, and the identity key provisioning
          matches on — Bambuddy does not enforce uniqueness here itself, so
          two declared entries sharing a name would collapse into one.
        '';
      };

      enabled = mkOption {
        type = types.bool;
        default = false;
        description = "Start this virtual printer. Bambuddy requires bindIp when set, and an access code unless targetPrinterSerial supplies one.";
      };

      mode = mkOption {
        type = types.enum ["archive" "review" "queue" "proxy"];
        default = "archive";
        description = ''
          What the virtual printer does with a job the slicer sends it:
          archive stores it, review holds it for manual approval, queue puts
          it in Bambuddy's print queue (autoDispatch then sends it on), proxy
          bridges straight through to targetPrinterSerial.
        '';
      };

      model = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = ''
          Which printer model the virtual printer advertises itself as, given
          either as the model name a person knows ("P2S") or as the SSDP
          model code Bambuddy stores ("N7"). Provisioning resolves a name to
          its code against the running instance's own model table, so the
          accepted set follows the deployed version rather than a copy kept
          here. Left null Bambuddy picks its own default (X1C).
        '';
      };

      accessCodeFile = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = ''
          Path to a file holding the access code a slicer must present to
          this virtual printer — agenix-decrypted under /run/agenix, never
          inline. Bambuddy requires the code to be exactly 8 characters, and
          requires one at all when enabled is set unless targetPrinterSerial
          is given (a non-proxy virtual printer with a target inherits the
          real printer's code, and anything set here would be ignored).
        '';
        example = "/run/agenix/bambuddy/virtual-printer-access-code";
      };

      targetPrinterSerial = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = ''
          Serial number of the real printer this virtual printer targets.
          Bambuddy's API wants its own internal row id instead, so
          provisioning resolves the serial against the live printer list at
          runtime; no database id is ever written down here. Required for
          proxy mode. If the target printer does not exist in Bambuddy yet,
          the virtual printer is reported as pending and retried.
        '';
      };

      autoDispatch = mkOption {
        type = types.bool;
        default = true;
        description = "Queue mode: send queued jobs to a printer automatically instead of waiting for a manual start. Matches Bambuddy's own default.";
      };

      queueForceColorMatch = mkOption {
        type = types.bool;
        default = false;
        description = "Queue mode: pin each slot's filament type and colour from the 3MF onto the queue item, so a printer with the wrong filament loaded is not dispatched to.";
      };

      saveAmsMapping = mkOption {
        type = types.bool;
        default = false;
        description = "Queue mode: keep the slicer's own resolved AMS slot assignment instead of re-deriving one from the file.";
      };

      gcodeInjection = mkOption {
        type = types.bool;
        default = false;
        description = "Allow Bambuddy to inject G-code into jobs received by this virtual printer.";
      };

      bindIp = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = ''
          Address the virtual printer's listeners bind to, and what a slicer
          points at. Required by Bambuddy whenever enabled is set, and unique
          across enabled virtual printers. This is an address the host must
          already carry — declaring it here does not configure an interface.
        '';
      };

      remoteInterfaceIp = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Optional address to advertise to slicers instead of bindIp, for reaching the virtual printer across a tunnel or a second interface.";
      };
    };
  };

  # Every rule below was read out of upstream's own create-time validation at
  # v1.2.5.3 (backend/app/api/routes/virtual_printers.py). Catching them at
  # eval time turns a 400 that only shows up in a journal into a build error.
  needBindIp = filter (vp: vp.enabled && vp.bindIp == null) cfg.virtualPrinters;
  needProxyTarget = filter (vp: vp.mode == "proxy" && vp.targetPrinterSerial == null) cfg.virtualPrinters;
  needAccessCode =
    filter
    (vp: vp.enabled && vp.mode != "proxy" && vp.accessCodeFile == null && vp.targetPrinterSerial == null)
    cfg.virtualPrinters;

  enabledVps = filter (vp: vp.enabled) cfg.virtualPrinters;

  vpNames = concatMapStringsSep ", " (vp: vp.name);

  serials = map (p: lib.toUpper p.serialNumber) cfg.printers;
  names = map (vp: vp.name) cfg.virtualPrinters;

  # The submodules are serialised whole: every option maps one-to-one onto a
  # field of the corresponding API request, so there is nothing to translate
  # here. Nothing secret goes in — accessCodeFile carries a path and the
  # script reads the file at runtime — so a world-readable store path is a
  # fine home for it.
  specFile = pkgs.writeText "bambuddy-provision.json" (builtins.toJSON {
    baseUrl = "http://${apiHost}:${toString cfg.port}";
    inherit (cfg) printers virtualPrinters;
  });

  # builtins.readFile rather than a bare path literal: reading the file yields
  # a string, so what lands in the store is hashed on that string's content.
  # `${./bambuddy-provision.py}` would instead embed a subpath of the single
  # whole-repo store copy of `self`, moving this derivation's identity on every
  # unrelated commit — see docs/architecture.md § Local Files As Build Inputs.
  # modules/media-ripping.nix reads ./import-disc.sh the same way.
  provisionScript = pkgs.writeText "bambuddy-provision.py" (builtins.readFile ./bambuddy-provision.py);

  declared = cfg.printers != [] || cfg.virtualPrinters != [];
in {
  options.custom.bambuddy = {
    printers = mkOption {
      type = types.listOf printerOptions;
      default = [];
      description = ''
        Real Bambu Lab printers to create in Bambuddy if they are not already
        there. Create-only: an entry that already exists (matched on
        serialNumber) is left exactly as it is, and removing an entry never
        deletes anything.

        Bambuddy verifies the MQTT connection to the printer before it will
        persist a row, so a printer that is powered off or unreachable cannot
        be added at all. Such an entry stays pending and is retried by
        bambuddy-provision.timer rather than failing for good.
      '';
      example = literalExpression ''
        [
          {
            name = "P2S";
            serialNumber = "0309CA000000000";
            ipAddress = "192.168.20.41";
            accessCodeFile = "/run/agenix/bambuddy/p2s-access-code";
            model = "P2S";
          }
        ]
      '';
    };

    virtualPrinters = mkOption {
      type = types.listOf virtualPrinterOptions;
      default = [];
      description = ''
        Virtual printers to create in Bambuddy if they are not already there.
        A virtual printer impersonates a Bambu printer on the LAN so a slicer
        can "send to printer" into Bambuddy. Create-only, matched on name,
        with the same non-destructive guarantees as printers above.

        A virtual printer's listeners are separate from the host firewall:
        custom.bambuddy.virtualPrinter.openFirewall in modules/bambuddy.nix is
        what makes them reachable from the LAN, and it opens them only on the
        bindIp of each enabled entry here — not on every address the host
        carries.
      '';
      example = literalExpression ''
        [
          {
            name = "Bambuddy";
            enabled = true;
            mode = "queue";
            model = "P2S";
            bindIp = "192.168.20.40";
            accessCodeFile = "/run/agenix/bambuddy/virtual-printer-access-code";
          }
        ]
      '';
    };
  };

  config = mkIf (cfg.enable && declared) {
    # Enabling a virtual printer and opening its ports are two different
    # switches, and nothing else connects them: Bambuddy starts the listeners
    # on bindIp as soon as an enabled row exists, while what a slicer on the
    # LAN can actually reach is the host firewall's business. Declaring one
    # without the other produces a virtual printer that looks healthy in the
    # UI and refuses every connection, with the refusal happening in the host
    # firewall (iptables here, see modules/bambuddy.nix) where Bambuddy's own
    # logs never see it.
    warnings =
      optional (enabledVps != [] && !cfg.virtualPrinter.openFirewall)
      "custom.bambuddy.virtualPrinters declares an enabled virtual printer (${vpNames enabledVps}) while custom.bambuddy.virtualPrinter.openFirewall is off. Bambuddy will start its listeners, but the host firewall will drop every slicer connection to them.";

    assertions = [
      {
        assertion = unique serials == serials;
        message = "custom.bambuddy.printers has entries sharing a serialNumber (compared uppercased, as Bambuddy stores them). Serial number is the identity key provisioning matches on, so duplicates would collapse into one printer.";
      }

      {
        assertion = unique names == names;
        message = "custom.bambuddy.virtualPrinters has entries sharing a name. Name is the identity key provisioning matches on, so duplicates would collapse into one virtual printer.";
      }

      {
        assertion = needBindIp == [];
        message = "custom.bambuddy.virtualPrinters entries with enabled = true must set bindIp — Bambuddy rejects the create with \"Bind IP is required when enabling\". Missing on: ${vpNames needBindIp}.";
      }

      {
        assertion = needProxyTarget == [];
        message = "custom.bambuddy.virtualPrinters entries with mode = \"proxy\" must set targetPrinterSerial — Bambuddy rejects the create with \"Target printer is required for proxy mode\". Missing on: ${vpNames needProxyTarget}.";
      }

      {
        assertion = needAccessCode == [];
        message = "custom.bambuddy.virtualPrinters entries with enabled = true and a non-proxy mode must set either accessCodeFile or targetPrinterSerial — Bambuddy rejects the create with \"Access code is required when enabling\". Missing on: ${vpNames needAccessCode}.";
      }
    ];

    systemd.services.bambuddy-provision = {
      description = "Reconcile declared printers into Bambuddy";
      documentation = ["https://github.com/maziggy/bambuddy"];
      after = ["bambuddy.service"];

      # Two triggers, deliberately. This one reconciles at boot and again
      # after any nixos-rebuild switch that changed the declared set (the
      # unit's ExecStart embeds the spec, so a changed declaration is a
      # changed unit, and switch-to-configuration restarts it); the timer
      # below covers everything that is not reconcilable at that instant.
      # Both are cheap — once every declared row exists the script makes two
      # GETs and exits.
      wantedBy = ["multi-user.target"];

      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${pkgs.python3}/bin/python3 ${provisionScript} ${specFile}";

        # Root because the access-code files are agenix-decrypted under
        # /run/agenix with no owner set, the same way this repo's other
        # root-read secrets are declared (see hosts/reliant/secrets.nix).
        # LoadCredential= would be the tidier way to hand them to an
        # unprivileged unit, but it fails the unit outright when the file is
        # absent, and "the agenix secret has not been created yet" is a
        # normal, expected state here that should produce an explanatory
        # journal line instead. No CapabilityBoundingSet= for the same class
        # of reason: a secret declared with an owner would need
        # CAP_DAC_READ_SEARCH for root to read it, and dropping capabilities
        # here would turn that into an unexplained permission error.
        User = "root";

        # The script waits up to 180s for /health and then spends up to ~8s
        # per printer in Bambuddy's MQTT probe; systemd's default
        # TimeoutStartSec (90s) would kill it inside that first wait.
        TimeoutStartSec = "600";

        # Deliberately no SuccessExitStatus=. The script exits 75
        # (EX_TEMPFAIL) for "declared, not reconcilable yet" and 1 for a real
        # error; both should leave the unit failed, because a printer that
        # has not appeared is a real unmet declaration and belongs in
        # `systemctl status bambuddy-provision.service` rather than buried.

        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        RestrictRealtime = true;
        LockPersonality = true;
      };
    };

    systemd.timers.bambuddy-provision = {
      description = "Retry reconciling declared printers into Bambuddy";
      wantedBy = ["timers.target"];

      # A timer rather than Restart=on-failure on the service. A printer that
      # is powered off can stay that way for days, and systemd's start rate
      # limiter would stop an auto-restart loop long before then and leave the
      # unit failed with no further attempts — the opposite of what is wanted.
      # A timer retries indefinitely at a fixed low rate, and between ticks
      # the last run's outcome stays visible in `systemctl status` instead of
      # being churned over.
      timerConfig = {
        OnBootSec = "10min";
        OnUnitInactiveSec = "15min";
        AccuracySec = "1min";
        Unit = "bambuddy-provision.service";
      };
    };
  };
}
