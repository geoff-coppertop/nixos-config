{
  age.identityPaths = [ "/var/lib/agenix/identity" ];

  age.secrets."thomasga/restic-password".file =
    ../secrets/thomasga/restic-password.age;
}
