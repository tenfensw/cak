#!/bin/sh -ve
test -z "$BASE_PATH" && BASE_PATH=/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/System/Library/Frameworks
FOUNDATION_PATH=$BASE_PATH/Foundation.framework

test -d bindings && rm -rvf bindings
mkdir -vp bindings

ruby make_c_bindings.rb -f"$FOUNDATION_PATH" --header=NSObject.h \
					     --header=NSString.h \
					     --header=NSCoder.h \
					     --header=NSData.h \
					     --header=NSURL.h \
					     --header=NSError.h \
					     --output-metainfo=bindings/minifoundation.txt \
					     --output-implementation=bindings/minifoundation.m > bindings/minifoundation.h

