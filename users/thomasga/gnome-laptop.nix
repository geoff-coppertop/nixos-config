{
  # Laptop-only display pin: fixes the internal eDP-1 panel's layout, scale, and
  # mode. Meaningless (and wrong) on a desktop driving external DisplayPort/HDMI
  # monitors, so it is imported only by the laptop host's home entry
  # (hosts/enterprise-d/home/thomasga.nix) rather than the shared desktop.nix.
  # The rest of the GNOME config (extensions, wallpaper, app folders, keybinds)
  # stays shared in users/thomasga/gnome.nix.
  home.file.".config/monitors.xml" = {
    force = true;
    text = ''
      <monitors version="2">
        <configuration>
          <logicalmonitor>
            <x>0</x>
            <y>0</y>
            <scale>2</scale>
            <primary>yes</primary>
            <monitor>
              <monitorspec>
                <connector>eDP-1</connector>
                <vendor>BOE</vendor>
                <product>NE135A1M-NY1</product>
                <serial>0x00000000</serial>
              </monitorspec>
              <mode>
                <width>2880</width>
                <height>1920</height>
                <rate>60.001</rate>
              </mode>
            </monitor>
          </logicalmonitor>
        </configuration>
      </monitors>
    '';
  };
}
