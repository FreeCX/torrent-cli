torrent-cli
---

Simple [transmission](https://transmissionbt.com/) rpc client

# How to build
```bash
$ zig build --release=fast
```

# How to use
```bash
$ zig build run -- --help
Simple transmission rpc client

USAGE:
    torrent_cli [OPTIONS] <COMMAND>

COMMANDS:
    add                 Add torrent
    start               Start torrent
    stop                Stop torrent
    delete              Delete torrent
    status              Show torrent stats

OPTIONS:
    -i, --host <HOST>       Transmission host  [default: 127.0.0.1]
    -p, --port <INT>        Transmission port  [default: 9091]
    -l, --level <STRING>    Log level  [choices: err, warn, info, debug]
    -h, --help              Print help
    -V, --version           Print version
```
