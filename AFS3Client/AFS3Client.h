//
// AFS3Client.h
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


#import "AFNetworking.h"
#import <CommonCrypto/CommonHMAC.h>

// See http://docs.amazonwebservices.com/AmazonS3/2006-03-01/index.html?RESTAccessPolicy.html for what these mean
extern NSString *const AFS3AccessPolicyPrivate; // This is the default in S3 when no access policy header is provided
extern NSString *const AFS3AccessPolicyPublicRead;
extern NSString *const AFS3AccessPolicyPublicReadWrite;
extern NSString *const AFS3AccessPolicyAuthenticatedRead;
extern NSString *const AFS3AccessPolicyBucketOwnerRead;
extern NSString *const AFIS3AccessPolicyBucketOwnerFullControl;

@interface AFS3Client : AFHTTPClient {
	NSString *_accessKey;
	NSString *_secretAccessKey;
	NSString *_sessionToken;
	// The access policy to use when PUTting a file (see the string constants at the top AFS3Client.h for details on what the possible options are)
	NSString *_accessPolicy;
}

@property (nonatomic, retain) NSString *accessPolicy;

/**
 Initializes an `AFS3Client` object with the specified base URL.
 
 @param accessKey Your S3 access key.
 @param secretKey Your S3 secret key.
 @param sessionToken Your S3 session token
 
 @discussion This is the initializes an AFS3Client with baseURL of 'https://s3.amazonaws.com'. This method is meant to be used with
 temporary security creditials from http://aws.amazon.com/iam/.
 
 @return The newly-initialized HTTP client
 */

- (id)initWithAccessKey:(NSString *)accessKey
        secretAccessKey:(NSString *)secretKey
           sessionToken:(NSString *)sessionToken;

/**
 Initializes an `AFS3Client` object with the specified base URL.
 
 @param accessKey Your S3 access key.
 @param secretKey Your S3 secret key.
 
 @WARNING!!! This should be used for tesing purposes only. Consider using initWithAccesToken:secretAccessKey:sessionToken along with
 temporary security credentials with http://aws.amazon.com/iam/. That way you don't have to store your root aws credentials in the app.
 
 @discussion This is the initializes an AFS3Client with baseURL of 'https://s3.amazonaws.com'.
 
 @return The newly-initialized HTTP client
 */
- (id)initWithAccessKey:(NSString *)accessKey
        secretAccessKey:(NSString *)secretKey;

/**
 PUT a new S3 object with the specified bucket and key
 
 @param bucket Name for the bucket the new object should be stored in
 @param key Path to new object ex. '/path/to/your/object.jpg'
 
 */
- (void)putObjectForData:(NSData *)data
              withBucket:(NSString *)bucket
                     key:(NSString *)key
                 success:(void (^)(AFHTTPRequestOperation *operation, id responseObject))success
                 failure:(void (^)(AFHTTPRequestOperation *operation, NSError *error))failure;

/**
 Overrides AFHTTPClient putPath function so we can post the data in the body of the request without using parameters
 
 @param path The path to be appended to the HTTP client's base URL and used as the request URL.
 @param data Data for the object.
 @param success A block object to be executed when the request operation finishes successfully. This block has no return value and takes two arguments: the created request operation and the object created from the response data of request.
 @param failure A block object to be executed when the request operation finishes unsuccessfully, or that finishes successfully, but encountered an error while parsing the resonse data. This block has no return value and takes two arguments:, the created request operation and the `NSError` object describing the network or parsing error that occurred.
 
 */
- (void)putPath:(NSString *)path
           data:(NSData *)data
        success:(void (^)(AFHTTPRequestOperation *operation, id responseObject))success
        failure:(void (^)(AFHTTPRequestOperation *operation, NSError *error))failure;

/**
 Overrides AFHTTPClient requestWithMethod function so we can post the data in the body of the request without using parameters
 
 Creates an `NSMutableURLRequest` object with the specified HTTP method and path.
 
 @param method The HTTP method for the request, such as `GET`, `POST`, `PUT`, or `DELETE`.
 @param path The path to be appended to the HTTP client's base URL and used as the request URL.
 @param data The data to be sent in the body of the HTTP Request.
 
 @return An `NSMutableURLRequest` object
 */
- (NSMutableURLRequest *)requestWithMethod:(NSString *)method
                                      path:(NSString *)path
                                      data:(NSData *)data;


/**
 Helper fuctions for creating the signature for S3 Requests
 */
+ (NSString *)stringByURLEncodingForS3Path:(NSString *)key;
+ (NSDateFormatter*)S3ResponseDateFormatter;
+ (NSDateFormatter*)S3RequestDateFormatter;
+ (NSString *)base64forData:(NSData *)theData;
+ (NSData *)HMACSHA1withKey:(NSString *)key forString:(NSString *)string;
+ (NSString *)mimeTypeForFileAtPath:(NSString *)path;

@end
