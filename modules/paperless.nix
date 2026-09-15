{ config, pkgs, ... }:

{
  services.paperless = {
    enable = true;
    address = "0.0.0.0";
    port = 28981;
    # from `just install`
    passwordFile = "/var/lib/paperless/admin-pass";
    settings = {
      PAPERLESS_OCR_LANGUAGE = "deu+eng";
    };
  };
}
