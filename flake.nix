{
  description = "Nim development environment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
  };

  outputs = { self, nixpkgs }:
    {
      devShells.x86_64-linux.default = 
        let
          pkgs = nixpkgs.legacyPackages.x86_64-linux;
        in
        pkgs.mkShell {
          buildInputs = with pkgs; [
            nim
            nimble
            curl
          ];
          
          shellHook = ''
            export LD_LIBRARY_PATH=${pkgs.curl}/lib:$LD_LIBRARY_PATH
          '';
        };
    };
} 