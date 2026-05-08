{ pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    alvr
  ];

  # ALVR streaming ports (TCP: control + data, UDP: video/audio stream)
  networking.firewall.allowedTCPPorts = [ 9943 9944 ];
  networking.firewall.allowedUDPPorts = [ 9944 ];
}
