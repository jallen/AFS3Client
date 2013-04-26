//
// AFS3Client.m
//
// Created by Jared Allen on 2/23/12.
// With code heavily borrowed from ASIHTTPRequest Library
// Copyright (c) 2012 Peapod Labs
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.

#import "AFS3Client.h"

NSString *const AFS3AccessPolicyPrivate = @"private";
NSString *const AFS3AccessPolicyPublicRead = @"public-read";
NSString *const AFS3AccessPolicyPublicReadWrite = @"public-read-write";
NSString *const AFS3AccessPolicyAuthenticatedRead = @"authenticated-read";
NSString *const AFS3AccessPolicyBucketOwnerRead = @"bucket-owner-read";
NSString *const AFIS3AccessPolicyBucketOwnerFullControl = @"bucket-owner-full-control";

@interface AFS3Client()
- (void)buildRequestHeadersForBucket:(NSString *)bucket key:(NSString *)key;
- (NSMutableDictionary *)S3Headers;
@end

@implementation AFS3Client

@synthesize accessPolicy = _accessPolicy;

- (id)initWithAccessKey:(NSString *)accessKey secretAccessKey:(NSString *)secretKey {
	if (!(self = [super initWithBaseURL:[NSURL URLWithString:@"https://s3.amazonaws.com"]])) return nil;
	
	_accessKey = [accessKey copy];
	_secretAccessKey = [secretKey copy];
	
	return self;
}

- (id)initWithAccessKey:(NSString *)accessKey secretAccessKey:(NSString *)secretKey sessionToken:(NSString *)sessionToken {
	if (!(self = [super initWithBaseURL:[NSURL URLWithString:@"https://s3.amazonaws.com"]])) return nil;
	
	_accessKey = [accessKey copy];
	_secretAccessKey = [secretKey copy];
	_sessionToken = [sessionToken copy];
	
	return self;
}

- (void)dealloc {
}

- (void)putObjectForData:(NSData *)data
              withBucket:(NSString *)bucket
                     key:(NSString *)key
                 success:(void (^)(AFHTTPRequestOperation *operation, id responseObject))success
                 failure:(void (^)(AFHTTPRequestOperation *operation, NSError *error))failure
{
	NSString *path = [NSString stringWithFormat:@"%@%@", bucket, key];
	
	[self buildRequestHeadersForBucket:bucket key:key];
	[self putPath:path data:data success:^(AFHTTPRequestOperation *operation, id responseObject) {
		if (success) {
			success(operation, responseObject);
		}
	} failure:^(AFHTTPRequestOperation *operation, NSError *error) {
		if (failure) {
			failure(operation, error);
		}
	}];
}

#pragma mark - AFHTTPClient

- (void)putPath:(NSString *)path
           data:(NSData *)data
        success:(void (^)(AFHTTPRequestOperation *operation, id responseObject))success
        failure:(void (^)(AFHTTPRequestOperation *operation, NSError *error))failure
{
	NSURLRequest *request = [self requestWithMethod:@"PUT" path:path data:data];
	AFHTTPRequestOperation *operation = [self HTTPRequestOperationWithRequest:request success:success failure:failure];
	[self enqueueHTTPRequestOperation:operation];
}

- (NSMutableURLRequest *)requestWithMethod:(NSString *)method
                                      path:(NSString *)path
                                      data:(NSData *)data
{
	NSMutableURLRequest *request = [super requestWithMethod:method path:path parameters:nil];
	[request setHTTPBody:data];
	
	return request;
}

#pragma mark - Private Methods

- (void)buildRequestHeadersForBucket:(NSString *)bucket key:(NSString *)key {
	NSString *dateString = [[AFS3Client S3RequestDateFormatter] stringFromDate:[NSDate date]];
	[self setDefaultHeader:@"Date" value:dateString];
	
	// Ensure our formatted string doesn't use '(null)' for the empty path
	NSString *canonicalizedResource = [NSString stringWithFormat:@"/%@%@", bucket,[AFS3Client stringByURLEncodingForS3Path:key]];;
	
	// Add a header for the access policy if one was set, otherwise we won't add one (and S3 will default to private)
	NSMutableDictionary *amzHeaders = [self S3Headers];
	
	NSString *canonicalizedAmzHeaders = @"";
	for (NSString *header in [[amzHeaders allKeys] sortedArrayUsingSelector:@selector(compare:)]) {
		canonicalizedAmzHeaders = [NSString stringWithFormat:@"%@%@:%@\n",canonicalizedAmzHeaders,[header lowercaseString],[amzHeaders objectForKey:header]];
		[self setDefaultHeader:header value:[amzHeaders objectForKey:header]];
	}
	// Put it all together
	NSString *stringToSign = [NSString stringWithFormat:@"%@\n\n\n%@\n%@%@", @"PUT", dateString, canonicalizedAmzHeaders, canonicalizedResource];
	NSString *signature = [AFS3Client base64forData:[AFS3Client HMACSHA1withKey:_secretAccessKey forString:stringToSign]];
	NSString *authorizationString = [NSString stringWithFormat:@"AWS %@:%@", _accessKey, signature];
	[self setDefaultHeader:@"Authorization" value:authorizationString];
}


- (NSMutableDictionary *)S3Headers {
	NSMutableDictionary *headers = [NSMutableDictionary dictionary];
	if (_accessPolicy) {
		[headers setObject:_accessPolicy forKey:@"x-amz-acl"];
	}
	if (_sessionToken) {
		[headers setObject:_sessionToken forKey:@"x-amz-security-token"];
	}
	return headers;
}

#pragma mark - Helper Methods

+ (NSString *)stringByURLEncodingForS3Path:(NSString *)key {
	if (!key) {
		return @"/";
	}
	NSString *path = (NSString *)CFBridgingRelease(CFURLCreateStringByAddingPercentEscapes(kCFAllocatorDefault, (CFStringRef)key, NULL, CFSTR(":?#[]@!$ &'()*+,;=\"<>%{}|\\^~`"), CFStringConvertNSStringEncodingToEncoding(NSUTF8StringEncoding)));
	if (![[path substringWithRange:NSMakeRange(0, 1)] isEqualToString:@"/"]) {
		path = [@"/" stringByAppendingString:path];
	}
	return path;
}

// Thanks to Tom Andersen for pointing out the threading issues and providing this code!
+ (NSDateFormatter *)S3ResponseDateFormatter {
	// We store our date formatter in the calling thread's dictionary
	// NSDateFormatter is not thread-safe, this approach ensures each formatter is only used on a single thread
	// This formatter can be reused 1000 times in parsing a single response, so it would be expensive to keep creating new date formatters
	NSMutableDictionary *threadDict = [[NSThread currentThread] threadDictionary];
	NSDateFormatter *dateFormatter = [threadDict objectForKey:@"ASIS3ResponseDateFormatter"];
	if (dateFormatter == nil) {
		dateFormatter = [[NSDateFormatter alloc] init];
		[dateFormatter setLocale:[[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"] ];
		[dateFormatter setTimeZone:[NSTimeZone timeZoneWithAbbreviation:@"UTC"]];
		[dateFormatter setDateFormat:@"yyyy-MM-dd'T'HH:mm:ss'.000Z'"];
		[threadDict setObject:dateFormatter forKey:@"ASIS3ResponseDateFormatter"];
	}
	return dateFormatter;
}

+ (NSDateFormatter *)S3RequestDateFormatter {
	NSMutableDictionary *threadDict = [[NSThread currentThread] threadDictionary];
	NSDateFormatter *dateFormatter = [threadDict objectForKey:@"ASIS3RequestHeaderDateFormatter"];
	if (dateFormatter == nil) {
		dateFormatter = [[NSDateFormatter alloc] init];
		// Prevent problems with dates generated by other locales (tip from: http://rel.me/t/date/)
		[dateFormatter setLocale:[[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"] ];
		[dateFormatter setTimeZone:[NSTimeZone timeZoneWithAbbreviation:@"UTC"]];
		[dateFormatter setDateFormat:@"EEE, d MMM yyyy HH:mm:ss Z"];
		[threadDict setObject:dateFormatter forKey:@"ASIS3RequestHeaderDateFormatter"];
	}
	return dateFormatter;
	
}

// From: http://www.cocoadev.com/index.pl?BaseSixtyFour

+ (NSString *)base64forData:(NSData *)theData {
	const uint8_t* input = (const uint8_t*)[theData bytes];
	NSInteger length = [theData length];
	
	static char table[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=";
	
	NSMutableData* data = [NSMutableData dataWithLength:((length + 2) / 3) * 4];
	uint8_t* output = (uint8_t*)data.mutableBytes;
	
	NSInteger i,i2;
	for (i=0; i < length; i += 3) {
		NSInteger value = 0;
		for (i2=0; i2<3; i2++) {
			value <<= 8;
			if (i+i2 < length) {
				value |= (0xFF & input[i+i2]);
			}
		}
		
		NSInteger theIndex = (i / 3) * 4;
		output[theIndex + 0] =                    table[(value >> 18) & 0x3F];
		output[theIndex + 1] =                    table[(value >> 12) & 0x3F];
		output[theIndex + 2] = (i + 1) < length ? table[(value >> 6)  & 0x3F] : '=';
		output[theIndex + 3] = (i + 2) < length ? table[(value >> 0)  & 0x3F] : '=';
	}
	
	return [[NSString alloc] initWithData:data encoding:NSASCIIStringEncoding];
}

// From: http://stackoverflow.com/questions/476455/is-there-a-library-for-iphone-to-work-with-hmac-sha-1-encoding

+ (NSData *)HMACSHA1withKey:(NSString *)key forString:(NSString *)string {
	NSData *clearTextData = [string dataUsingEncoding:NSUTF8StringEncoding];
	NSData *keyData = [key dataUsingEncoding:NSUTF8StringEncoding];
	
	uint8_t digest[CC_SHA1_DIGEST_LENGTH] = {0};
	
	CCHmacContext hmacContext;
	CCHmacInit(&hmacContext, kCCHmacAlgSHA1, keyData.bytes, keyData.length);
	CCHmacUpdate(&hmacContext, clearTextData.bytes, clearTextData.length);
	CCHmacFinal(&hmacContext, digest);
	
	return [NSData dataWithBytes:digest length:CC_SHA1_DIGEST_LENGTH];
}

+ (NSString *)mimeTypeForFileAtPath:(NSString *)path {
	if (![[[NSFileManager alloc] init]fileExistsAtPath:path]) {
		return nil;
	}
	// Borrowed from http://stackoverflow.com/questions/2439020/wheres-the-iphone-mime-type-database
	CFStringRef UTI = UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension, (__bridge CFStringRef)[path pathExtension], NULL);
	CFStringRef MIMEType = UTTypeCopyPreferredTagWithClass (UTI, kUTTagClassMIMEType);
    NSString *mimeType = (__bridge_transfer NSString *)(MIMEType);
	CFRelease(UTI);
	if (!MIMEType) {
		return @"application/octet-stream";
	}
	return mimeType;
}


@end
