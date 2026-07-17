# Apple TV -> projector + receiver power control via a Broadlink RM4 mini.
#
# Turns the projector and receiver on when the Apple TV wakes, and off again
# ten minutes after it sleeps (turning it back on within those ten minutes
# cancels the shutoff, since the state trigger's `for:` timer resets).
#
# Two pieces are inherently manual — they cannot be declared here — and must be
# done once through the Home Assistant UI at https://homeassistant.coppertop.ca:
#
#   1. Add the integrations (Settings -> Devices & Services -> Add Integration):
#      - Apple TV  -> pair it; note its media_player entity id
#      - Broadlink -> discovers the RM4 mini; note its remote entity id
#      If those entity ids differ from `media_player.apple_tv` / `remote.rm4_mini`
#      below, update them here.
#
#   2. Learn the four IR commands the automations send (Developer Tools ->
#      Actions -> remote.learn_command), pressing the matching button on each
#      device's own remote when the RM4 light comes on:
#        projector/PowerOn  projector/PowerOff  receiver/PowerOn  receiver/PowerOff
#      If a device only has a single power TOGGLE, learn it once (e.g.
#      projector/PowerToggle) and send that in both automations instead — but a
#      toggle can desync if the device is switched by other means.
#
# Volume is intentionally not handled here. HA never receives the Siri Remote's
# physical volume presses (it is a client of the Apple TV, not a listener), so
# it cannot relay them through the RM4. With the receiver on HDMI-ARC/eARC, use
# CEC instead: enable HDMI-CEC on the receiver and projector, then set the Apple
# TV's Settings -> Remotes and Devices -> Volume Control to Auto. (Fallback if
# the projector won't pass CEC audio-system commands: Volume Control -> Learn
# New Device, which programs the Siri Remote's own IR emitter.)
{
  services.home-assistant = {
    # apple_tv and broadlink are config-flow integrations (set up in the UI, see
    # above); listing them here installs the components so they can be added.
    extraComponents = ["apple_tv" "broadlink"];

    config.automation = [
      {
        id = "appletv_on_power_on_av";
        alias = "Apple TV on -> power on projector + receiver";
        mode = "single";
        triggers = [
          {
            trigger = "state";
            entity_id = "media_player.apple_tv";
            from = ["off" "standby"];
            to = ["idle" "playing" "paused" "on"];
          }
        ];
        conditions = [];
        actions = [
          {
            action = "remote.send_command";
            target.entity_id = "remote.rm4_mini";
            data = {
              device = "projector";
              command = "PowerOn";
            };
          }
          # small gap so the two IR bursts from one blaster don't collide
          {delay = "00:00:01";}
          {
            action = "remote.send_command";
            target.entity_id = "remote.rm4_mini";
            data = {
              device = "receiver";
              command = "PowerOn";
            };
          }
        ];
      }
      {
        id = "appletv_off_10min_power_off_av";
        alias = "Apple TV off 10 min -> power off projector + receiver";
        mode = "single";
        triggers = [
          {
            trigger = "state";
            entity_id = "media_player.apple_tv";
            to = ["off" "standby"];
            for = "00:10:00";
          }
        ];
        conditions = [];
        actions = [
          {
            action = "remote.send_command";
            target.entity_id = "remote.rm4_mini";
            data = {
              device = "projector";
              command = "PowerOff";
            };
          }
          {delay = "00:00:01";}
          {
            action = "remote.send_command";
            target.entity_id = "remote.rm4_mini";
            data = {
              device = "receiver";
              command = "PowerOff";
            };
          }
        ];
      }
    ];
  };
}
