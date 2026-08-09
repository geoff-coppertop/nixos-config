{
  pkgs,
  agenixCli,
}: let
  localFile = import ./local-file.nix;

  # `src = ../tools;` here would coerce to a subpath of the whole-repo store
  # copy, so this derivation's identity would move on every unrelated commit.
  # See docs/architecture.md § Local Files As Build Inputs.
  tools-src =
    pkgs.runCommand "nixos-config-tools" {
      src = localFile {
        path = ../tools;
        name = "nixos-config-tools-src";
      };
    } ''
      cp -r $src $out
    '';

  provision = pkgs.writeShellApplication {
    name = "provision";
    runtimeInputs = with pkgs; [python3 age openssh git coreutils gnugrep findutils];
    text = ''
      export PYTHONPATH="${tools-src}:''${PYTHONPATH:-}"
      exec python3 ${tools-src}/provision.py "$@"
    '';
  };

  install = pkgs.writeShellApplication {
    name = "install";
    runtimeInputs = with pkgs; [python3 age openssh git coreutils util-linux parted zstd gnugrep findutils udisks2];
    text = ''
      export PYTHONPATH="${tools-src}:''${PYTHONPATH:-}"
      exec python3 ${tools-src}/install.py "$@"
    '';
  };

  secretEdit = pkgs.writeShellApplication {
    name = "secret-edit";
    runtimeInputs = [agenixCli pkgs.python3 pkgs.coreutils pkgs.git pkgs.gnugrep];
    text = ''
      export PYTHONPATH="${tools-src}:''${PYTHONPATH:-}"
      exec python3 ${tools-src}/secret_edit.py "$@"
    '';
  };

  secretRekey = pkgs.writeShellApplication {
    name = "secret-rekey";
    runtimeInputs = [agenixCli pkgs.python3 pkgs.git pkgs.gnugrep pkgs.findutils];
    text = ''
      export PYTHONPATH="${tools-src}:''${PYTHONPATH:-}"
      exec python3 ${tools-src}/secret_rekey.py "$@"
    '';
  };
in {
  provision = {
    type = "app";
    program = "${provision}/bin/provision";
    meta.description = "Enroll a new NixOS machine (generate age identity and SSH keys)";
  };

  install = {
    type = "app";
    program = "${install}/bin/install";
    meta.description = "Install a NixOS machine (disko, SD card flash, or WSL instructions)";
  };

  secret-edit = {
    type = "app";
    program = "${secretEdit}/bin/secret-edit";
    meta.description = "Edit encrypted agenix secrets";
  };

  secret-rekey = {
    type = "app";
    program = "${secretRekey}/bin/secret-rekey";
    meta.description = "Rekey agenix secrets with new host keys";
  };
}
