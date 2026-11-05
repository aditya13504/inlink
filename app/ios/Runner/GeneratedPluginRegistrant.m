//
//  Generated file. Do not edit.
//

// clang-format off

#import "GeneratedPluginRegistrant.h"

#if __has_include(<cryptography_flutter/CryptographyFlutterPlugin.h>)
#import <cryptography_flutter/CryptographyFlutterPlugin.h>
#else
@import cryptography_flutter;
#endif

#if __has_include(<flutter_secure_storage/FlutterSecureStoragePlugin.h>)
#import <flutter_secure_storage/FlutterSecureStoragePlugin.h>
#else
@import flutter_secure_storage;
#endif

#if __has_include(<mobile_scanner/MobileScannerPlugin.h>)
#import <mobile_scanner/MobileScannerPlugin.h>
#else
@import mobile_scanner;
#endif

#if __has_include(<sqflite_sqlcipher/SqfliteSqlCipherPlugin.h>)
#import <sqflite_sqlcipher/SqfliteSqlCipherPlugin.h>
#else
@import sqflite_sqlcipher;
#endif

@implementation GeneratedPluginRegistrant

+ (void)registerWithRegistry:(NSObject<FlutterPluginRegistry>*)registry {
  [CryptographyFlutterPlugin registerWithRegistrar:[registry registrarForPlugin:@"CryptographyFlutterPlugin"]];
  [FlutterSecureStoragePlugin registerWithRegistrar:[registry registrarForPlugin:@"FlutterSecureStoragePlugin"]];
  [MobileScannerPlugin registerWithRegistrar:[registry registrarForPlugin:@"MobileScannerPlugin"]];
  [SqfliteSqlCipherPlugin registerWithRegistrar:[registry registrarForPlugin:@"SqfliteSqlCipherPlugin"]];
}

@end
