## Zig Version Manager

### No dependency on external command line tools or non-zig libraries.

This is a toy project that I play with. Its main purpose is to help me learn [Zig](https://ziglang.org/).

It's been tried and somewhat works in Linux, MacOS and Windows 10.

To build it you need zig version [0.12.0-dev.1297+a9e66ed73](https://ziglang.org/download) or newer.

Build with `zig build -Doptimize=ReleaseFast`

```bash
 Usage:
    zvm install <version> [<arch-os>]
    zvm uninstall <version> [<arch-os>]
    zvm use <version> [<arch-os>]
    zvm list [-r|--remote]
    zvm version
```

Example usage:
```bash
$ zvm install master

$ zvm list

$ zvm list -r
```
### Config file `config.json`
 ```json
{
    "zig_root": "path/to/folder/with/all/zig/versions"
}
```
