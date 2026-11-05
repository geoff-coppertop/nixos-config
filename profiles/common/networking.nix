{
  services.avahi = {
    enable = true;
    nssmdns4 = true;
    openFirewall = true;

    settings.publish = {
      disable-publishing = false;
      publish-addresses = true;
    };
  };
}
