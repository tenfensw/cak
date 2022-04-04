#!/bin/sh -ve
test -z "$BASE_PATH" && BASE_PATH=/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/System/Library/Frameworks
FOUNDATION_PATH=$BASE_PATH/Foundation.framework

FOUNDATION_BLACKLIST_PARAM="usingComparator:"

test -d bindings && rm -rfv bindings
mkdir -vp bindings

ruby make_c_bindings.rb -f"$FOUNDATION_PATH" --header=NSObject.h \
					     --header=NSString.h \
					     --header=NSCoder.h \
					     --header=NSData.h \
					     --header=NSURL.h \
					     --header=NSLocale.h \
					     --header=NSArray.h \
					     --header=NSDictionary.h \
					     -v --blacklist-arguments="$FOUNDATION_BLACKLIST_PARAM" \
					     --output-metainfo=bindings/minifoundation.txt \
					     --output-implementation=bindings/minifoundation.m > bindings/minifoundation.h
