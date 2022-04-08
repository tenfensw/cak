#!/bin/sh -ve
test -z "$BASE_PATH" && BASE_PATH=/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/System/Library/Frameworks
FOUNDATION_PATH=$BASE_PATH/Foundation.framework
APPKIT_PATH=$BASE_PATH/AppKit.framework

FOUNDATION_BLACKLIST_PARAM="usingComparator:"
FOUNDATION_HEADERS=`echo Object String Coder Data URL Locale Array Dictionary | xargs printf '\-\-header=NS%s.h '`
test "$1" = "full-foundation" && FOUNDATION_HEADERS='--header=Foundation.h'

rm -rfv *.dSYM *.bin
test -d bindings && rm -rfv bindings

test "$1" = "distclean" && exit 0

mkdir -vp bindings

# Foundation.framework -> minifoundation

/usr/bin/ruby make_c_bindings.rb -f"$FOUNDATION_PATH" $FOUNDATION_HEADERS \
				 -v --blacklist-arguments="$FOUNDATION_BLACKLIST_PARAM" \
				 --blacklist-methods="NSLocale@init" \
				 --output-metainfo=bindings/minifoundation.txt \
				 --output-implementation=bindings/minifoundation.m > bindings/minifoundation.h
# allow direct access just in case
echo "void* CakOIDGetDirect(CakOIDRef vl);" >> bindings/minifoundation.h
echo "void* CakOIDGetDirect(CakOIDRef vl) { return (vl ? vl->rth : NULL); }" >> bindings/minifoundation.m

clang -c -o bindings/minifoundation.o -Wno-incompatible-pointer-types -Wno-objc-method-access \
				      -Wno-return-type -Wno-format-security -fno-objc-arc \
				      -Ibindings -g bindings/minifoundation.m
ar crs bindings/minifoundation.a bindings/minifoundation.o && rm -f bindings/minifoundation.o
clang -o demo.bin -g -fno-objc-arc -Ibindings -framework Foundation demo.c bindings/minifoundation.a

APPKIT_PREDEFINED_CLASSES=`cat bindings/minifoundation.txt | grep '@interface *' | cut -d ' ' -f2 | xargs printf '\-\-class=%s '`

echo "#pragma once" > bindings/cakappkit.h
echo "#include \"minifoundation.h\"" >> bindings/cakappkit.h
ruby make_c_bindings.rb -f"$APPKIT_PATH" --output-metainfo=bindings/cakappkit.txt \
					 --output-implementation=bindings/cakappkit.m \
					 $APPKIT_PREDEFINED_CLASSES \
					 --header=NSPanel.h \
					 --header=NSApplication.h \
					 --no-oid-definition \
					 -v >> bindings/cakappkit.h
