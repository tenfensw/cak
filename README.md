# Cak

__Automatic Cocoa C bindings__

*Copyright (C) Tim K 2018-2022. https://xfen.page/*

## Building

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

## Usage

Cak basically creates wrapper C functions around Objective-C interface methods. All of them are named more or less like their original counterparts, except for the casing & ``CakOID<interface name?>`` prefix.

For example, let's say you want to create a new instance of ``NSString`` from a UTF-8 C string. You would do it this way directly in ObjC:

```objective-c
NSString* myString = [[NSString alloc] initWithUTF8String:"Greetings from ObjC!"];
```

And using Cak:

```c
CakOIDRef myString = CakOIDNSStringInitWithUTF8String(CakOIDNSStringAlloc(), "Greetings from Cak!");
```

Looks clunky in C, but for a quirky project like this this will do (+ hey, at least the naming is intuitive cause it's preserved from the original methods) :P

Another example with ``NSURL`` taken from Apple's website:

```objc
NSURL* baseURL = [NSURL fileURLWithPath:@"file:///path/to/user/"];
NSURL* URL = [NSURL URLWithString:@"folder/file.html" relativeToURL:baseURL];
NSLog(@"absoluteURL = %@", [URL absoluteURL]);
```

With Cak:

```c
// there is no @"" shorthand in C, obv, so we have to declare the original strings seperately first
CakOIDRef originalPath = CakOIDNSStringStringWithUTF8String("file:///path/to/user/");
CakOIDRef pathToAppend = CakOIDNSStringStringWithUTF8String("folder/file.html");

CakOIDRef baseURL = CakOIDNSURLFileURLWithPath(originalPath);
CakOIDRef URL = CakOIDNSURLURLWithStringRelativeToURL(pathToAppend, baseURL);
const char* absoluteURL = CakOIDNSStringUTF8String(CakOIDNSURLAbsoluteURL(URL));

printf("absoluteURL = %s\n", absoluteURL);

// free the memory now
CakOIDNSStringRelease(originalPath);
CakOIDNSStringRelease(pathToAppend);
CakOIDNSURLRelease(baseURL);
CakOIDNSURLRelease(URL);
```

Notice that (obviously) Objnuall ective-C's ARC is not possible in C, so you have to manage memory with ``Retain`` and ``Release`` manually.

To link:

```bash
$ clang -o urldemo -I$PATH_TO_CAK_SOURCES/bindings -std=c99 -fno-objc-arc urldemo.c $PATH_TO_CAK_SOURCES/bindings/minifoundation.a
```

See ``demo.c`` too for a fully working example.

## Why does this project exist?

There are people who want to make Mac apps using native Apple technologies, but who also want to make their apps portable. At least one person like this exists and that's me.

Also making a project that allows people to make Mac apps in pure C sounds fun :P

## License

MIT, unless stated otherwise in the sources