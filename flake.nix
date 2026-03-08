{
  description = "Graphical Package Manager for Manjaro Linux with Alpm, AUR, Appstream, Flatpak and Snap support";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  nixConfig = {
    extra-substituters = [ "https://cache.garnix.io" ];
    extra-trusted-public-keys = [ "cache.garnix.io:CTFPyKSLcx5RMJKfLo5EEPUObbA78b0YQ2DTCJXqr9g=" ];
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};

        libpamac = pkgs.stdenv.mkDerivation {
          pname = "libpamac";
          version = "11.7.4";

          src = pkgs.fetchFromGitHub {
            owner = "manjaro";
            repo = "libpamac";
            rev = "master";
            sha256 = "0r1452nzlvgf8mal7ydsa4hg0f7ryysjzskz9g2dwa5q4aznq5h8";
          };

          nativeBuildInputs = with pkgs; [
            meson
            ninja
            vala
            pkg-config
            gettext
            gobject-introspection
          ];

          postPatch = ''
            sed -i "s/version : '>=16.0'/version : '>=15.0'/" src/meson.build
            sed -i "s/handle.disable_sandbox_filesystem = /handle.disable_sandbox = /" src/alpm_config.vala
            sed -i "/handle.disable_sandbox_syscalls = /d" src/alpm_config.vala
          '';

          buildInputs = with pkgs; [
            glib
            pacman
            libarchive
            json-glib
            libsoup_3
            polkit
            appstream
            flatpak
          ];

          mesonFlags = [
            "--sysconfdir=/etc"
            "--localstatedir=/var"
          ];

          # We need to use install_dir to avoid installing to /etc
          preConfigure = ''
            export mesonFlags="$mesonFlags --sysconfdir=$out/etc"
          '';
        };

        pamac = pkgs.stdenv.mkDerivation {
          pname = "pamac";
          version = "11.7.4";

          src = ./.;

          nativeBuildInputs = with pkgs; [
            meson
            ninja
            vala
            pkg-config
            gettext
            wrapGAppsHook4
          ];

          buildInputs = with pkgs; [
            glib
            gtk3
            gtk4
            libadwaita
            libnotify
            libpamac
          ];

          mesonFlags = [
            "-Djemalloc=false"
            "--sysconfdir=/etc"
          ];

          preConfigure = ''
            export mesonFlags="$mesonFlags --sysconfdir=$out/etc"
          '';
        };
      in
      {
        packages.libpamac = libpamac;
        packages.pamac = pamac;
        packages.default = pamac;

        devShells.default = pkgs.mkShell {
          inputsFrom = [ pamac ];
          nativeBuildInputs = with pkgs; [
            # dev tools
          ];
        };
      }
    );
}
