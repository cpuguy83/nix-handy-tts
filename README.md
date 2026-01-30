# Nix Flake for Handy

A Nix flake for [Handy](https://github.com/cjpais/Handy) - a free, open source, offline speech-to-text application.

## Installation

### With Home Manager (recommended)

Add the flake to your inputs:

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager.url = "github:nix-community/home-manager";
    handy.url = "github:YOUR_USERNAME/nix-handy-tts";
  };
}
```

Import the module and enable it:

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
nix run github:YOUR_USERNAME/nix-handy-tts
```

Or build and run:

```bash
nix build github:YOUR_USERNAME/nix-handy-tts
./result/bin/handy &
```

## Usage Notes

### First Run

On first launch, Handy will prompt you to select a speech-to-text model. Models are downloaded to `~/.local/share/com.pais.handy/`.

### Push-to-Talk

For global hotkeys to work, you may need to:

1. Be in the `input` group: `sudo usermod -aG input $USER` (then log out/in)
2. Enable "Experimental Features" in Handy settings
3. Switch to "Handy Keys" keyboard implementation in settings

## Packages

The flake provides several packages:

- `default` / `handy` - Handy wrapped in an FHS environment (recommended)
- `handy-unwrapped` - Unwrapped Handy binary
- `frontend` - Just the frontend assets

## Development

Enter the development shell:

```bash
nix develop
```

This provides all build dependencies and copies the Handy source to `./handy-src/`.

## Platform Support

Currently only `x86_64-linux` is supported.

## Known Issues

- Bluetooth audio devices may not appear in device selection
- Some ALSA warnings about pulse/jack/oss may appear in logs (harmless)
- The "Handy Keys" experimental keyboard implementation is more reliable than the default

## License

This flake is provided as-is. Handy itself is MIT licensed.
