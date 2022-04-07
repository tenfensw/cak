typedef struct _NSRange NSRange; // TODO: fix

#include <stdio.h>
#include "minifoundation.h"

#define kCakOIDNSUnicodeStringEncoding 10

int main() {
	CakOIDRef testString = CakOIDNSStringAlloc();
	CakOIDNSStringInitWithUTF8String(testString, "Greetings from Cak!");

	printf("%s\n", CakOIDNSStringCStringUsingEncoding(testString, kCakOIDNSUnicodeStringEncoding));

	CakOIDNSStringRelease(testString);
	return 0;
}
