# Cak

__Automatic Cocoa C bindings__

*Copyright (C) Tim K 2018-2022. https://xfen.page/*

## Usage

You'll need:

- Ruby 2.0+ (built-in in macOS)
- Xcode Command Line Tools 
  - Regular Xcode 10+ should work too, but it was not tested & you'll have to specify the ``BASE_PATH`` environment variable to the path where ``MacOSX.sdk/Frameworks`` is in Xcode.app, that's pain so just install CLI tools instead

```bash
git clone https://github.com/tenfensw/cak.git
cd cak
./bind.sh
```

The resulting bindings are going to be in the ``bindings`` folder.

## Why does this project exist?

There are people who want to make Mac apps using native Apple technologies, but who also want to make their apps portable. At least one person like this exists and that's me.

Also making a project that allows people to make Mac apps in pure C sounds fun :P

## License

MIT, unless stated otherwise in the sources