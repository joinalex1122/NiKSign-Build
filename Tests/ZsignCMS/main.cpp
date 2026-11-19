#include "bundle.h"
#include "openssl.h"
int main(int argc, char **argv) {
    if (argc != 4) return 2;
    ZSignAsset asset;
    if (!asset.Init("", argv[2], argv[3], "", "fixture password", false, false, false)) return 3;
    ZBundle bundle;
    return bundle.SignFolder(&asset, argv[1], "", "", "", {}, {}, true, false, false, false) ? 0 : 4;
}
