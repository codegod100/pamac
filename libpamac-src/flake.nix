{
  description = "Pamac library";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
      in
      {
        packages.libpamac = pkgs.stdenv.mkDerivation {
          pname = "libpamac";
          version = "11.7.4";

          src = ./.;

          nativeBuildInputs = with pkgs; [
            meson
            ninja
            vala
            pkg-config
            gettext
            gobject-introspection
          ];

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

          preConfigure = ''
            export mesonFlags="$mesonFlags --sysconfdir=$out/etc"
          '';
        };
        packages.default = self.packages.${system}.libpamac;
      }
    );
}
