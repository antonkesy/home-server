{ settings, ... }:

{
  services.paperless = {
    enable = true;
    address = "0.0.0.0";
    port = settings.ports.paperless;
    # from `just install`
    passwordFile = "/var/lib/paperless/admin-pass";
    settings = {
      PAPERLESS_OCR_LANGUAGE = settings.ocrLanguages;
    };
  };
}
