{ config, pkgs, ... }:

let
  # Realtek r8125 2.5G Ethernet driver
  r8125 = config.boot.kernelPackages.callPackage ({ stdenv, lib, kernel, fetchFromGitHub }:
    stdenv.mkDerivation rec {
      pname = "r8125";
      version = "9.015.00";

      src = fetchFromGitHub {
        owner = "antonkesy";
        repo = "r8125";
        rev = "80c1b25847c996d3b92a92d1ac6856b0c5dff4b6";
        hash = "sha256-5P5FLT9rV6MdHlp9xKj0Zyb1Q2fajZu7h9YPRdxnWOw=";
      };

      sourceRoot = "source/src";
      hardeningDisable = [ "pic" "format" ];
      nativeBuildInputs = kernel.moduleBuildDependencies;

      makeFlags = [
        "KERNELDIR=${kernel.dev}/lib/modules/${kernel.modDirVersion}/build"
      ];

      installPhase = ''
        mkdir -p $out/lib/modules/${kernel.modDirVersion}/kernel/drivers/net/ethernet/realtek
        cp r8125.ko $out/lib/modules/${kernel.modDirVersion}/kernel/drivers/net/ethernet/realtek/
      '';

      meta = with lib; {
        description = "Realtek RTL8125 2.5 Gigabit Ethernet driver";
        homepage = "https://github.com/antonkesy/r8125";
        license = licenses.gpl2Only;
        platforms = platforms.linux;
        maintainers = [];
      };
    }) {};
in
{
  # Realtek r8125 network driver
  boot.extraModulePackages = [ r8125 ];
  boot.kernelModules = [ "r8125" ];
}
