{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (lib) concatStringsSep escapeShellArg mkEnableOption mkIf mkMerge mkOption optionals types;
  cfg = config.custom.dcsServer;
  onOff = b:
    if b
    then "1"
    else "0";
  # /run/current-system/sw/bin, not a versioned /nix/store path — a sudoers
  # command match against a store path breaks on every systemd package
  # update; the sw/bin symlink is the stable target NixOS itself points at.
  systemctlBin = "/run/current-system/sw/bin/systemctl";
  dcsUnits = "podman-dcs-server.service podman-dcs-srs-server.service";
in {
  options.custom.dcsServer = {
    enable = mkEnableOption "DCS World dedicated server (Aterfax OCI image under podman)";

    image = mkOption {
      type = types.str;
      default = "docker.io/aterfax/dcs-world-dedicated-server:latest";
      description = "Fully-qualified OCI image reference.";
    };

    dataDir = mkOption {
      type = types.str;
      default = "/var/lib/dcs-server";
      description = "Host directory bind-mounted to /config (wine prefix, DCS install, Saved Games).";
    };

    autoInstall = mkOption {
      type = types.bool;
      default = true;
      description = "DCSAUTOINSTALL: download and install the DCS server on first container start.";
    };

    autoStart = mkOption {
      type = types.bool;
      default = false;
      description = "AUTOSTART: launch the DCS server when the container starts. Requires saved login credentials and auto-login in the DCS launcher (first-boot GUI step).";
    };

    dcsModules = mkOption {
      type = types.listOf types.str;
      default = [];
      example = ["MARIANAISLANDS_terrain"];
      description = "DCSMODULES: terrain/module identifiers installed by the auto-installer.";
    };

    environmentFiles = mkOption {
      type = types.listOf types.str;
      default = [];
      example = ["/run/agenix/dcs-server-env"];
      description = "Environment files for secrets, e.g. PASSWORD= for the web desktop.";
    };

    gamePort = mkOption {
      type = types.port;
      default = 10308;
      description = "Multiplayer game traffic (TCP+UDP).";
    };

    voiceChat = {
      enable = mkEnableOption "expose the DCS in-game VoIP port";

      port = mkOption {
        type = types.port;
        default = 10309;
        description = "DCS in-game VoIP (TCP+UDP).";
      };
    };

    srs = {
      # Not bundled with the DCS image at all — Aterfax/DCS-World-Dedicated-Server-Docker
      # issue #74 tracks that as an unimplemented feature request. This runs the
      # separate purpose-built jaycadi/dcs-srs-server image as its own container
      # instead of relying on a manual Windows .exe install inside the DCS desktop.
      enable = mkEnableOption "run a DCS-SRS (SimpleRadio) voice server container, separate from the DCS server image";

      image = mkOption {
        type = types.str;
        default = "docker.io/jaycadi/dcs-srs-server:2.3.6.0";
        description = "Fully-qualified OCI image reference for the SRS server.";
      };

      dataDir = mkOption {
        type = types.str;
        default = "/var/lib/dcs-srs-server";
        description = "Host directory bind-mounted for SRS presets.";
      };

      port = mkOption {
        type = types.port;
        default = 5002;
        description = "DCS-SRS voice traffic (TCP+UDP).";
      };

      restApi = {
        enable = mkEnableOption "SRS REST API";

        port = mkOption {
          type = types.port;
          default = 8080;
          description = "SRS REST API port (TCP).";
        };
      };

      environmentFiles = mkOption {
        type = types.listOf types.str;
        default = [];
        example = ["/run/agenix/dcs-srs-env"];
        description = "Env files for secrets, e.g. EXTERNAL_AWACS_MODE_BLUE_PASSWORD=/EXTERNAL_AWACS_MODE_RED_PASSWORD=.";
      };
    };

    desktopPort = mkOption {
      type = types.port;
      default = 3000;
      description = "Webtop web desktop, bound to 127.0.0.1 only — reach via ssh -L.";
    };

    webGuiPort = mkOption {
      type = types.port;
      default = 8088;
      description = "Eagle Dynamics remote-control WebGUI, bound to 127.0.0.1 only — reach via ssh -L.";
    };

    webGuiBindAddress = mkOption {
      type = types.str;
      default = "127.0.0.1";
      description = "Bind address for the WebGUI port publish. Override only when pairing with a firewall rule restricting source access (e.g. a cross-host Traefik proxy) — the WebGUI has weak default auth.";
    };

    openFirewall = mkOption {
      type = types.bool;
      default = true;
      description = "Open the game/VoIP/SRS ports in the host firewall.";
    };

    startAtBoot = mkOption {
      type = types.bool;
      default = true;
      description = "Bring the DCS and DCS-SRS containers up automatically on boot. Set false when custom.dcsServer.control is used for on-demand start/stop — the systemd units still exist and can be started manually/via the control service, they just don't come back on their own after a reboot.";
    };

    control = {
      enable = mkEnableOption "a small on-demand start/stop control page + webhook for the DCS/DCS-SRS containers, for use behind a cross-host Traefik proxy (see docs/homelab-network.md)";

      bindAddress = mkOption {
        type = types.str;
        default = "127.0.0.1";
        description = "Bind address for the control page and webhook ports. Override only when pairing with a firewall rule restricting source access — neither the page nor the webhook has auth of its own; real auth in front of it is a deliberate, not-yet-done follow-up (see docs/homelab-network.md).";
      };

      pagePort = mkOption {
        type = types.port;
        default = 9090;
        description = "Port for the static control page (nginx).";
      };

      webhookPort = mkOption {
        type = types.port;
        default = 9091;
        description = "Port for the start/stop/status/upload-mission webhook (adnanh/webhook), reached at /hooks/dcs-start, /hooks/dcs-stop, /hooks/dcs-status, /hooks/dcs-upload-mission.";
      };

      missionsDir = mkOption {
        type = types.str;
        default = "${cfg.dataDir}/.wine/drive_c/users/abc/Saved Games/DCS.dcs_serverrelease/Missions";
        description = "Host path DCS itself reads missions from (inside the persistent Wine profile). Uploaded .miz files via /hooks/dcs-upload-mission land here.";
      };
    };
  };

  config = mkIf cfg.enable (mkMerge [
    {
      virtualisation.oci-containers = {
        backend = "podman";

        containers.dcs-server = {
          inherit (cfg) image environmentFiles;
          autoStart = cfg.startAtBoot;

          environment = {
            PUID = "1000";
            PGID = "1000";
            TZ = config.time.timeZone;
            DCSAUTOINSTALL = onOff cfg.autoInstall;
            AUTOSTART = onOff cfg.autoStart;
            DCSMODULES = concatStringsSep " " cfg.dcsModules;
          };

          volumes = ["${cfg.dataDir}:/config"];

          ports =
            [
              "${toString cfg.gamePort}:10308/tcp"
              "${toString cfg.gamePort}:10308/udp"
              # Admin surfaces stay loopback-only (webtop has weak default auth);
              # reach via: ssh -L 3000:localhost:3000 -L 8088:localhost:8088 <host>
              "127.0.0.1:${toString cfg.desktopPort}:3000/tcp"
              "${cfg.webGuiBindAddress}:${toString cfg.webGuiPort}:8088/tcp"
            ]
            ++ optionals cfg.voiceChat.enable [
              "${toString cfg.voiceChat.port}:10309/tcp"
              "${toString cfg.voiceChat.port}:10309/udp"
            ];
        };
      };

      # The linuxserver init chowns /config to PUID:PGID itself.
      systemd.tmpfiles.rules = ["d ${cfg.dataDir} 0755 root root -"];

      networking.firewall = mkIf cfg.openFirewall {
        allowedTCPPorts = [cfg.gamePort] ++ optionals cfg.voiceChat.enable [cfg.voiceChat.port];
        allowedUDPPorts = [cfg.gamePort] ++ optionals cfg.voiceChat.enable [cfg.voiceChat.port];
      };
    }

    (mkIf cfg.srs.enable {
      virtualisation.oci-containers.containers.dcs-srs-server = {
        inherit (cfg.srs) image;
        inherit (cfg.srs) environmentFiles;
        autoStart = cfg.startAtBoot;

        environment = {
          SERVER_PORT = toString cfg.srs.port;
          SERVER_IP = "0.0.0.0";
          HTTP_SERVER_ENABLED =
            if cfg.srs.restApi.enable
            then "true"
            else "false";
          HTTP_SERVER_PORT = toString cfg.srs.restApi.port;
        };

        volumes = ["${cfg.srs.dataDir}/Presets:/docker/dcs-srs/Presets"];

        ports =
          [
            "${toString cfg.srs.port}:${toString cfg.srs.port}/tcp"
            "${toString cfg.srs.port}:${toString cfg.srs.port}/udp"
          ]
          ++ optionals cfg.srs.restApi.enable [
            "${toString cfg.srs.restApi.port}:${toString cfg.srs.restApi.port}/tcp"
          ];
      };

      systemd.tmpfiles.rules = ["d ${cfg.srs.dataDir}/Presets 0755 root root -"];

      networking.firewall = mkIf cfg.openFirewall {
        allowedTCPPorts = [cfg.srs.port] ++ optionals cfg.srs.restApi.enable [cfg.srs.restApi.port];
        allowedUDPPorts = [cfg.srs.port];
      };
    })

    (mkIf cfg.control.enable (let
      # is-active is a read-only D-Bus query — no sudo needed. start/stop
      # change system state, so those run through the sudoers rule below
      # instead of as this (unprivileged) service's own user.
      #
      # `systemctl is-active` exits non-zero whenever the unit isn't
      # active — i.e. almost always, since this is an on-demand server.
      # webhook only echoes a command's stdout back to the client when it
      # exits 0 (confirmed live: without the `|| true` here, /hooks/dcs-status
      # returned a bare 500 instead of the status text for every state
      # except "active", which made the control page's Start/Stop
      # permanently show "Unknown" and stay disabled in exactly the state
      # you need them most — server stopped). The text on stdout is what
      # we actually want; the process exit code is not.
      statusScript = pkgs.writeShellScript "dcs-control-status" ''
        ${systemctlBin} is-active podman-dcs-server.service || true
      '';
      startScript = pkgs.writeShellScript "dcs-control-start" ''
        exec /run/wrappers/bin/sudo -n ${systemctlBin} start ${dcsUnits}
      '';
      stopScript = pkgs.writeShellScript "dcs-control-stop" ''
        exec /run/wrappers/bin/sudo -n ${systemctlBin} stop ${dcsUnits}
      '';

      # Mission uploads are privilege-separated the same way start/stop are:
      # the webhook's own (unprivileged, firewall-restricted-only) user never
      # writes into the DCS install directly. It stages the upload under its
      # own home, then hands off to a fixed, zero-argument sudo command that
      # does the real placement -- so the only thing sudoers has to trust is
      # "run this exact script", not an arbitrary filename passed on a
      # command line (which sudoers can't safely pattern-match). All
      # filename sanitization happens *inside* the privileged script, which
      # treats the staged name file as untrusted input regardless of what
      # the unprivileged step already did to it.
      uploadStageDir = "/var/lib/dcs-control/uploads";
      uploadStageFile = "${uploadStageDir}/pending.miz";
      uploadNameFile = "${uploadStageDir}/pending.name";
      installMissionScript = pkgs.writeShellScript "dcs-control-install-mission" ''
        set -eu
        dest=${escapeShellArg cfg.control.missionsDir}
        mkdir -p "$dest"
        raw=$(cat ${escapeShellArg uploadNameFile} 2>/dev/null || true)
        base=$(basename -- "''${raw:-mission.miz}")
        safe=$(printf '%s' "$base" | tr -c 'A-Za-z0-9._-' '_')
        case "$safe" in
          .*|"") safe="mission.miz" ;;
        esac
        case "$safe" in
          *.miz) ;;
          *) safe="$safe.miz" ;;
        esac
        target="$dest/$safe"
        if [ -e "$target" ]; then
          ts=$(date +%Y%m%d-%H%M%S)
          safe="''${safe%.miz}-$ts.miz"
          target="$dest/$safe"
        fi
        install -o 1000 -g 1000 -m 0644 ${escapeShellArg uploadStageFile} "$target"
        rm -f ${escapeShellArg uploadStageFile} ${escapeShellArg uploadNameFile}
        printf '%s\n' "$safe"
      '';
      uploadScript = pkgs.writeShellScript "dcs-control-upload-mission" ''
        set -eu
        mkdir -p ${escapeShellArg uploadStageDir}
        cp "$HOOK_MISSION" ${escapeShellArg uploadStageFile}
        printf '%s' "''${HOOK_FILENAME:-mission.miz}" > ${escapeShellArg uploadNameFile}
        exec /run/wrappers/bin/sudo -n ${installMissionScript}
      '';
      hooksFile = pkgs.writeText "dcs-control-hooks.yaml" ''
        - id: dcs-status
          execute-command: "${statusScript}"
          command-working-directory: "/tmp"
          http-method: GET
          include-command-output-in-response: true
        - id: dcs-start
          execute-command: "${startScript}"
          command-working-directory: "/tmp"
          http-method: POST
        - id: dcs-stop
          execute-command: "${stopScript}"
          command-working-directory: "/tmp"
          http-method: POST
        - id: dcs-upload-mission
          execute-command: "${uploadScript}"
          command-working-directory: "/tmp"
          http-method: POST
          include-command-output-in-response: true
          pass-file-to-command:
            - source: raw-request-body
              name: mission
              envname: HOOK_MISSION
          pass-environment-to-command:
            - source: header
              name: X-Filename
              envname: HOOK_FILENAME
      '';
      controlPage = pkgs.writeTextDir "index.html" ''
        <!doctype html>
        <html>
          <head>
            <meta charset="utf-8" />
            <title>DCS Server Control</title>
            <meta name="viewport" content="width=device-width, initial-scale=1" />
            <style>
              :root {
                color-scheme: light dark;
                --bg: #f4f5f7;
                --card: #fff;
                --border: #dde1e6;
                --text: #1a1d21;
                --muted: #6b7280;
                --active: #1a7f37;
                --inactive: #a40e26;
                --pending: #9a6700;
              }
              @media (prefers-color-scheme: dark) {
                :root {
                  --bg: #1a1d21;
                  --card: #24282e;
                  --border: #383e46;
                  --text: #e8eaed;
                  --muted: #9aa1ac;
                  --active: #4caf6d;
                  --inactive: #e05a6f;
                  --pending: #d8a84e;
                }
              }
              * { box-sizing: border-box; }
              body {
                font-family: system-ui, -apple-system, sans-serif;
                background: var(--bg);
                color: var(--text);
                min-height: 100vh;
                margin: 0;
                display: flex;
                align-items: center;
                justify-content: center;
                padding: 1.5rem;
              }
              main {
                background: var(--card);
                border: 1px solid var(--border);
                border-radius: 0.75rem;
                padding: 2rem 2.5rem;
                max-width: 24rem;
                width: 100%;
                text-align: center;
              }
              h1 {
                font-size: 1.25rem;
                margin: 0 0 1.25rem;
              }
              .status-row {
                display: flex;
                align-items: center;
                justify-content: center;
                gap: 0.5rem;
                margin-bottom: 1.5rem;
                color: var(--muted);
                font-size: 0.95rem;
              }
              #status {
                font-weight: 600;
                text-transform: capitalize;
              }
              #status.active { color: var(--active); }
              #status.inactive, #status.failed { color: var(--inactive); }
              #status.activating, #status.deactivating, #status.warming { color: var(--pending); }
              .dot {
                width: 0.55rem;
                height: 0.55rem;
                border-radius: 50%;
                background: currentColor;
                flex-shrink: 0;
              }
              .dot.spin {
                animation: pulse 1s ease-in-out infinite;
              }
              @keyframes pulse {
                0%, 100% { opacity: 1; }
                50% { opacity: 0.3; }
              }
              .buttons {
                display: flex;
                gap: 0.75rem;
                justify-content: center;
              }
              button {
                font: inherit;
                font-size: 0.95rem;
                font-weight: 600;
                padding: 0.6rem 1.5rem;
                border-radius: 0.5rem;
                border: 1px solid var(--border);
                background: var(--bg);
                color: var(--text);
                cursor: pointer;
                transition: opacity 0.15s;
              }
              button:hover:not(:disabled) { opacity: 0.85; }
              button:disabled {
                cursor: not-allowed;
                opacity: 0.4;
              }
              .upload-row {
                margin-top: 1.5rem;
                padding-top: 1.5rem;
                border-top: 1px solid var(--border);
              }
              .upload-row input[type="file"] {
                font-size: 0.85rem;
                color: var(--muted);
                max-width: 100%;
              }
              #uploadBtn {
                display: block;
                margin: 0.75rem auto 0;
              }
              #uploadStatus {
                margin-top: 0.5rem;
                font-size: 0.85rem;
                color: var(--muted);
                min-height: 1.1em;
              }
            </style>
          </head>
          <body>
            <main>
              <h1>DCS Server Control</h1>
              <div class="status-row">
                <span class="dot" id="dot"></span>
                <span id="status">checking…</span>
              </div>
              <div class="buttons">
                <button id="start">Start</button>
                <button id="stop">Stop</button>
              </div>
              <div class="upload-row">
                <input type="file" id="missionFile" accept=".miz" />
                <button id="uploadBtn">Upload Mission</button>
                <div id="uploadStatus"></div>
              </div>
            </main>
            <script>
              const startBtn = document.getElementById('start');
              const stopBtn = document.getElementById('stop');
              const statusEl = document.getElementById('status');
              const dotEl = document.getElementById('dot');
              const PENDING = {inflightStart: false, inflightStop: false};

              // systemd reports the container "active" as soon as the
              // podman process launches — well before DCS itself has
              // finished booting inside Wine (see hosts/excelsior/README.md
              // § First-Time Service Setup: "Mission list is empty, server
              // not started." can persist for a while after this). There's
              // no real readiness signal available here (that would mean
              // parsing DCS's own log or probing the game port), so this is
              // a fixed, approximate grace period during which "active" is
              // shown as "warming" instead of a plain ready-looking green
              // — better than claiming readiness we can't actually confirm.
              // Adjust WARMUP_MS if it's consistently too short/long.
              const WARMUP_MS = 90000;
              let warmingUntil = 0;

              function applyState(state) {
                const warming = state === 'active' && Date.now() < warmingUntil;
                const displayState = warming ? 'warming' : state;
                statusEl.textContent = displayState;
                statusEl.className = displayState;
                dotEl.className = 'dot ' + displayState;
                const transitional = state === 'activating' || state === 'deactivating' || warming;
                dotEl.classList.toggle('spin', transitional);
                // Only "inactive"/"failed" can start; only "active" can stop
                // (warming up still counts as active — stopping mid-boot is
                // valid, starting an already-running container is not).
                startBtn.disabled = PENDING.inflightStart || !(state === 'inactive' || state === 'failed');
                stopBtn.disabled = PENDING.inflightStop || state !== 'active';
                startBtn.textContent = PENDING.inflightStart ? 'Starting…' : 'Start';
                stopBtn.textContent = PENDING.inflightStop ? 'Stopping…' : 'Stop';
              }

              // Two independent triggers call refresh(): the 5s poll timer
              // and the explicit call right after a click's POST resolves.
              // A stale response can land after a newer one (e.g. the
              // periodic poll started just before a click, but resolves
              // after the click's own post-action refresh) — seq guards
              // against applying it. Clearing a PENDING flag on any
              // "not transitional" read was worse: a periodic poll that
              // happens to land between the click and systemd actually
              // starting the transition would read the still-old
              // "inactive" state and immediately clear inflightStart,
              // flipping the button back to enabled mid-action. Each
              // flag now only clears on its actual terminal outcome.
              let seq = 0;
              async function refresh() {
                const mySeq = ++seq;
                try {
                  const r = await fetch('/hooks/dcs-status');
                  const state = (await r.text()).trim();
                  if (mySeq !== seq) return;
                  if (r.ok) {
                    if (PENDING.inflightStart && (state === 'active' || state === 'failed')) {
                      if (state === 'active') warmingUntil = Date.now() + WARMUP_MS;
                      PENDING.inflightStart = false;
                    }
                    if (PENDING.inflightStop && (state === 'inactive' || state === 'failed')) {
                      PENDING.inflightStop = false;
                    }
                  }
                  applyState(r.ok ? state : 'unknown');
                } catch {
                  if (mySeq !== seq) return;
                  applyState('unknown');
                }
              }
              startBtn.onclick = async () => {
                PENDING.inflightStart = true;
                applyState(statusEl.textContent);
                await fetch('/hooks/dcs-start', {method: 'POST'});
                refresh();
              };
              stopBtn.onclick = async () => {
                PENDING.inflightStop = true;
                applyState(statusEl.textContent);
                await fetch('/hooks/dcs-stop', {method: 'POST'});
                refresh();
              };

              const missionFile = document.getElementById('missionFile');
              const uploadBtn = document.getElementById('uploadBtn');
              const uploadStatus = document.getElementById('uploadStatus');
              uploadBtn.onclick = async () => {
                const file = missionFile.files[0];
                if (!file) {
                  uploadStatus.textContent = 'Choose a .miz file first.';
                  return;
                }
                uploadBtn.disabled = true;
                uploadStatus.textContent = 'Uploading ' + file.name + '…';
                try {
                  const r = await fetch('/hooks/dcs-upload-mission', {
                    method: 'POST',
                    headers: {
                      'Content-Type': 'application/octet-stream',
                      'X-Filename': file.name,
                    },
                    body: file,
                  });
                  const text = (await r.text()).trim();
                  uploadStatus.textContent = r.ok
                    ? 'Uploaded as ' + text + '. Load it from the mission list in the local webtop desktop.'
                    : 'Upload failed.';
                } catch {
                  uploadStatus.textContent = 'Upload failed.';
                } finally {
                  uploadBtn.disabled = false;
                  missionFile.value = "";
                }
              };

              refresh();
              setInterval(refresh, 5000);
            </script>
          </body>
        </html>
      '';
    in {
      users.users.dcs-control = {
        isSystemUser = true;
        group = "dcs-control";
      };
      users.groups.dcs-control = {};

      # Minimal-privilege grant for a small number of automated actions:
      # this user, these exact command lines — nothing broader.
      # installMissionScript takes zero arguments (see its definition
      # above) specifically so this sudoers entry never has to trust a
      # user-controlled filename on a command line.
      security.sudo.extraRules = [
        {
          users = ["dcs-control"];
          commands = [
            {
              command = "${systemctlBin} start ${dcsUnits}";
              options = ["NOPASSWD"];
            }
            {
              command = "${systemctlBin} stop ${dcsUnits}";
              options = ["NOPASSWD"];
            }
            {
              command = "${installMissionScript}";
              options = ["NOPASSWD"];
            }
          ];
        }
      ];

      systemd.tmpfiles.rules = ["d ${uploadStageDir} 0750 dcs-control dcs-control -"];

      systemd.services.dcs-control-webhook = {
        description = "Webhook endpoints for on-demand DCS server start/stop";
        wantedBy = ["multi-user.target"];
        serviceConfig = {
          ExecStart = "${pkgs.webhook}/bin/webhook -hooks ${hooksFile} -ip ${cfg.control.bindAddress} -port ${toString cfg.control.webhookPort} -urlprefix hooks";
          User = "dcs-control";
          Restart = "on-failure";
        };
      };

      services.nginx = {
        enable = true;
        virtualHosts.dcs-control = {
          listen = [
            {
              addr = cfg.control.bindAddress;
              port = cfg.control.pagePort;
            }
          ];
          root = controlPage;
        };
      };
    }))
  ]);
}
