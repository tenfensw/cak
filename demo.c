typedef struct _NSRange NSRange; // TODO: fix

#include <stdio.h>
#include "minifoundation.h"

int main() {
	const char* pathChecked = "/usr/bin/ruby"; // exists on all Macs

	// convert this to NSString*
	CakOIDRef pathCheckedAsString = CakOIDNSStringStringWithUTF8String(pathChecked);

	// now make an NSURL*
	CakOIDRef pathCheckedAsURL = CakOIDNSURLFileURLWithPath(pathCheckedAsString);
	if (CakOIDNSURLCheckResourceIsReachableAndReturnError(pathCheckedAsURL, NULL))
		printf("%s is reachable\n", pathChecked);

	// free the memory
	CakOIDNSURLRelease(pathCheckedAsURL);
	CakOIDNSStringRelease(pathCheckedAsString);
	return 0;
}
