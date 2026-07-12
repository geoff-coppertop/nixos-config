{
  description = "Abigail Thomas";
  # Locked so no credential lives in git. The account is real and fully
  # home-manager-managed; a wheel user sets an interactive password on the
  # machine with `sudo passwd thomasar` after the first rebuild.
  hashedPassword = "!";
  # Flat-gray placeholder — swap for a real image the same way, no other
  # wiring changes needed.
  avatar = ./files/placeholder.png;
}
