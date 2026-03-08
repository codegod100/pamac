{
  description = "Graphical Package Manager for Manjaro Linux with Alpm, AUR, Appstream, Flatpak and Snap support";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
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

        pyside-pamac = pkgs.stdenv.mkDerivation {
          pname = "pyside-pamac";
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
            mkdir -p $out/bin $out/share/pyside-pamac
            cp main.py Main.qml $out/share/pyside-pamac/
            
            makeWrapper ${pkgs.python3}/bin/python3 $out/bin/pyside-pamac \
              --add-flags "$out/share/pyside-pamac/main.py" \
              --set GI_TYPELIB_PATH "${libpamac}/lib/girepository-1.0:${pkgs.glib.out}/lib/girepository-1.0:${pkgs.gobject-introspection.out}/lib/girepository-1.0" \
              --set LD_LIBRARY_PATH "${libpamac}/lib" \
              --set PAMAC_CONF "${libpamac}/etc/pamac.conf" \
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
        packages.pyside-pamac = pyside-pamac;
        packages.default = pamac;

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
