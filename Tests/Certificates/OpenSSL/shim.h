// The host regression harness uses Homebrew's canonical include paths.
// The iOS application still links its pinned OpenSSL XCFramework.
#include <openssl/bio.h>
#include <openssl/evp.h>
#include <openssl/pkcs12.h>
#include <openssl/provider.h>
#include <openssl/rsa.h>
#include <openssl/x509.h>
#include <openssl/x509v3.h>
