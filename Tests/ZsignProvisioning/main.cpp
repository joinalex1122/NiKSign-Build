#include "bundle.h"
#include "macho.h"

// Real native SignFolder/resource sealing on a synthetic Mach-O. No Apple identity or installation claim.
int main(int argc, char** argv) {
    if (argc != 5) return 2;
    ZSignAsset asset;
    asset.m_bAdhoc = true;
    asset.m_strTeamId = "TEAMFIXTURE";
    asset.m_strApplicationId = argv[4];
    asset.m_strEntitleData = "<?xml version=\"1.0\"?><plist version=\"1.0\"><dict/></plist>";
    if (!ZFile::ReadFile(argv[2], asset.m_strProvData)) return 3;
    ZBundle bundle;
    if (!bundle.SignFolder(&asset, argv[1], "", "", "", {}, {}, true, false, false, string(argv[3]) == "remove")) return 4;
    return 0;
}
