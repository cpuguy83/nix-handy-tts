# Nix Flake for Handy

A Nix flake for [Handy](https://github.com/cjpais/Handy) - a free, open source, offline speech-to-text application.

## Installation

### With Home Manager (recommended)

Add the flake to your inputs:

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    home-manager.url = "github:nix-community/home-manager";
    handy = {
      url = "github:YOUR_USERNAME/nix-handy-stt";
      inputs.nixpkgs.follows = "nixpkgs";
      # If you also use rust-overlay in your flake:
      # inputs.rust-overlay.follows = "rust-overlay";
    };
  };
}
```

> **Note:** This flake is built against `nixpkgs-unstable`. If you use
> `inputs.nixpkgs.follows` to point to a different nixpkgs channel (e.g., a
> stable release), you may encounter library compatibility issues. For best
> results, ensure your nixpkgs also follows `nixpkgs-unstable`.

Import the module and enable it. You'll also need to apply the overlay to get `pkgs.handy`:

```nix
{ inputs, pkgs, ... }:

{
  imports = [ inputs.handy.homeManagerModules.default ];

  nixpkgs.overlays = [ inputs.handy.overlays.default ];

  services.handy.enable = true;
}
```

Alternatively, you can specify the package explicitly without using the overlay:

```nix
{ inputs, pkgs, ... }:

{
  imports = [ inputs.handy.homeManagerModules.default ];

  services.handy = {
    enable = true;
    package = inputs.handy.packages.${pkgs.system}.default;
  };
}
```

### Direct installation

Run directly:

```bash
nix run github:YOUR_USERNAME/nix-handy-stt
```

Or build and run:

```bash
nix build github:YOUR_USERNAME/nix-handy-stt
./result/bin/handy &
```

## Usage Notes

### First Run

On first launch, Handy will prompt you to select a speech-to-text model. Models are downloaded to `~/.local/share/com.pais.handy/`.

## Packages

The flake provides several packages:

- `default` / `handy` - Handy wrapped in an FHS environment (recommended)
- `handy-unwrapped` - Unwrapped Handy binary
- `frontend` - Just the frontend assets

## Home Manager Module

- `homeManagerModules.default` / `homeManagerModules.handy` - Installs Handy and its desktop entry

## Overlay

- `overlays.default` - Adds `handy` and `handy-unwrapped` to pkgs

## Development

Enter the development shell:

```bash
nix develop
```

This provides all build dependencies and copies the Handy source to `./handy-src/`.

## Known Issues

- Bluetooth audio devices may not appear in device selection
- Some ALSA warnings about pulse/jack/oss may appear in logs (harmless)
- The "Handy Keys" experimental keyboard implementation is more reliable than the default

## License

This flake is provided as-is. Handy itself is MIT licensed.
