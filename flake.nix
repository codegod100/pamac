{
  description = "Graphical Package Manager for Manjaro Linux with Alpm, AUR, Appstream, Flatpak and Snap support";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    libpamac-src.url = "github:codegod100/libpamac-nix";
  };

  nixConfig = {
    extra-substituters = [
      "https://cache.garnix.io"
      "https://codegod100.cachix.org"
    ];
    extra-trusted-public-keys = [
      "cache.garnix.io:CTFPyKSLcx5RMJKfLo5EEPUObbA78b0YQ2DTCJXqr9g="
      "codegod100.cachix.org-1:LZFL5VrR644WUjleS3bLbVeOdzlXqzKznQWvD5MVthA="
    ];
  };

  outputs = { self, nixpkgs, flake-utils, libpamac-src }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        libpamac = libpamac-src.packages.${system}.libpamac;

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

        pamac-pyside = pkgs.stdenv.mkDerivation {
          pname = "pamac-pyside";
          version = "0.1.0";
          src = ./pyside-kirigami;

          nativeBuildInputs = with pkgs; [
            makeWrapper
            qt6.wrapQtAppsHook
          ];

          buildInputs = with pkgs; [
            pkgs.python3
            pkgs.python3Packages.pyside6
            pkgs.python3Packages.pygobject3
            pkgs.kdePackages.kirigami
            pkgs.kdePackages.qqc2-desktop-style
            libpamac
          ];

          installPhase = ''
            mkdir -p $out/bin $out/share/pamac-pyside
            cp main.py Main.qml $out/share/pamac-pyside/

            makeWrapper ${pkgs.python3}/bin/python3 $out/bin/pamac-pyside \
              --add-flags "$out/share/pamac-pyside/main.py" \
              --set GI_TYPELIB_PATH "${libpamac}/lib/girepository-1.0:${pkgs.glib.out}/lib/girepository-1.0:${pkgs.gobject-introspection.out}/lib/girepository-1.0" \
              --set LD_LIBRARY_PATH "${libpamac}/lib" \
              --set PAMAC_CONF "/etc/pamac.conf" \
              --set PACMAN_CONF "/etc/pacman.conf" \
              --set PACMAN_DBPATH "/var/lib/pacman/" \
              --set LIBGL_ALWAYS_SOFTWARE "1" \
              --set QT_QUICK_BACKEND "software" \
              --prefix PYTHONPATH : "$PYTHONPATH:${pkgs.python3Packages.pyside6}/${pkgs.python3.sitePackages}:${pkgs.python3Packages.pygobject3}/${pkgs.python3.sitePackages}" \
              --prefix QML2_IMPORT_PATH : "${pkgs.kdePackages.kirigami}/lib/qt-6/qml"
          '';
        };
        in
        {
        packages.libpamac = libpamac;
        packages.pamac = pamac;
        packages.pamac-pyside = pamac-pyside;
        packages.default = pamac-pyside;

        devShells.default = pkgs.mkShell {
          inputsFrom = [ pamac ];
          buildInputs = with pkgs; [
            python3
            python3Packages.pyside6
            python3Packages.pygobject3
            kdePackages.kirigami
            kdePackages.qqc2-desktop-style
          ];
          shellHook = ''
            export GI_TYPELIB_PATH="${libpamac}/lib/girepository-1.0:$GI_TYPELIB_PATH"
            export LD_LIBRARY_PATH="${libpamac}/lib:$LD_LIBRARY_PATH"
            export QML2_IMPORT_PATH="${pkgs.kdePackages.kirigami}/lib/qt-6/qml:$QML2_IMPORT_PATH"
          '';
        };
      }
    );
}
