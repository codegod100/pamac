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
            
            # Patch hardcoded config paths to check environment variables
            sed -i 's|"/etc/pamac.conf"|GLib.Environment.get_variable("PAMAC_CONF") ?? "/etc/pamac.conf"|g' src/pamac_config.vala
            sed -i 's|"/etc/pacman.conf"|GLib.Environment.get_variable("PACMAN_CONF") ?? "/etc/pacman.conf"|g' src/pamac_config.vala
            
            # Additional check: make sure AlpmConfig constructor in src/pamac_config.vala is also patched
            sed -i 's|new AlpmConfig ("/etc/pacman.conf")|new AlpmConfig (GLib.Environment.get_variable("PACMAN_CONF") ?? "/etc/pacman.conf")|g' src/pamac_config.vala
            
            # Patch AlpmConfig.vala to use env var for EVERYTHING
            sed -i 's|parse_file (conf_path)|parse_file (GLib.Environment.get_variable("PACMAN_CONF") ?? "/etc/pacman.conf")|g' src/alpm_config.vala
            sed -i 's|AlpmConfig (string path)|AlpmConfig (string _unused_path)|g' src/alpm_config.vala
            sed -i 's|conf_path = path;|conf_path = GLib.Environment.get_variable("PACMAN_CONF") ?? "/etc/pacman.conf";|g' src/alpm_config.vala
            sed -i 's|siglevel = Alpm.SigLevel.PACKAGE_OPTIONAL |siglevel = Alpm.SigLevel.USE_DEFAULT |g' src/alpm_config.vala
            sed -i '/parse_file (conf_path);/a \ \ \ \ \ \ \ \ \ \ \ \ siglevel = Alpm.SigLevel.USE_DEFAULT;' src/alpm_config.vala

            # Patch AlpmConfig defaults
            sed -i 's|"/var/lib/pacman/"|GLib.Environment.get_variable("PACMAN_DBPATH") ?? "/var/lib/pacman/"|g' src/alpm_config.vala
            sed -i 's|"/var/log/pacman.log"|GLib.Environment.get_variable("PACMAN_LOGFILE") ?? "/var/log/pacman.log"|g' src/alpm_config.vala
            
            # Enable AUR by default in the installed config
            sed -i "s/#EnableAUR/EnableAUR/" data/config/pamac.conf
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
        packages.pyside-pamac = pyside-pamac;
        packages.default = pyside-pamac;

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
