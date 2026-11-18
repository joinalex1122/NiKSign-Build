#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
nik_audit_pass=${1:?Pass must be 1 or 2}
case "$nik_audit_pass" in 1|2) ;; *) exit 2 ;; esac
# These are ignored generated products, never application input or user documents.
rm -rf build NiKSign.xcodeproj
python3 scripts/check-integration.py
python3 scripts/check-dependencies.py
python3 Tests/minizip_test.py
python3 Tests/patch_v9_test.py
python3 Tests/verify_ipa_test.py
node Tests/web.test.js
xcrun swiftc Vendor/3105/ThreeOneOSFive/helpers/PatchProjectModels.swift Vendor/3105/ThreeOneOSFive/helpers/PatchPackageCodec.swift Tests/CodecSmoke.swift -o /tmp/nik-codec-test
/tmp/nik-codec-test
xcrun swiftc -DNIKSIGN_STANDALONE_TEST Vendor/3105/ThreeOneOSFive/helpers/PatchProjectModels.swift Vendor/3105/ThreeOneOSFive/helpers/PatchPackageCodec.swift Vendor/3105/ThreeOneOSFive/helpers/PatchWorkspaceService.swift Native/Dependencies/NiKPatchV9Engine.swift Tests/PatchV9Smoke.swift -o /tmp/nik-patch-v9-test
/tmp/nik-patch-v9-test
xcrun swiftc -DNIKSIGN_STANDALONE_TEST Vendor/3105/ThreeOneOSFive/helpers/PatchProjectModels.swift Vendor/3105/ThreeOneOSFive/helpers/PatchPackageCodec.swift Vendor/3105/ThreeOneOSFive/helpers/PatchWorkspaceService.swift Native/Dependencies/NiKPatchV9Engine.swift Tests/PatchV9TransactionSmoke.swift -o /tmp/nik-patch-v9-transaction-test
/tmp/nik-patch-v9-transaction-test
xcrun swiftc Native/NiKFileImport.swift Native/Integration/SupportPolicy.swift Tests/FileImportSmoke.swift -o /tmp/nik-file-import-test
/tmp/nik-file-import-test
xcrun swiftc Native/Models/NiKSigningModels.swift Native/Models/NiKSigningJob.swift Tests/SigningJobsSmoke.swift -o /tmp/nik-signing-jobs-test
xcrun swiftc Native/Models/NiKPlistValue.swift Native/Models/NiKCertificateModels.swift Native/Models/NiKCertificateCompatibility.swift Tests/CertificateCompatibilitySmoke.swift -o /tmp/nik-cert-compat-test
/tmp/nik-cert-compat-test
/tmp/nik-signing-jobs-test
xcrun swiftc Native/Models/NiKFileRecoveryRecord.swift Native/Services/NiKFileDigest.swift Native/Services/NiKFileRecoveryStore.swift Tests/FileRecoverySmoke.swift -o /tmp/nik-file-recovery-test
/tmp/nik-file-recovery-test
xcrun swiftc Native/Models/NiKSigningModels.swift Native/Models/NiKSigningJob.swift Native/Models/NiKFileRecoveryRecord.swift Native/Models/NiKDiagnosticReport.swift Tests/DiagnosticsSmoke.swift -o /tmp/nik-diagnostics-test
/tmp/nik-diagnostics-test
xcrun swiftc Native/Models/NiKFileRecoveryRecord.swift Native/Models/NiKEditableTextDocument.swift Native/Services/NiKFileDigest.swift Tests/TextDocumentSmoke.swift -o /tmp/nik-text-document-test
/tmp/nik-text-document-test
xcrun swiftc Native/Models/NiKSigningModels.swift Native/Models/NiKLibraryItem.swift Native/Services/NiKLibraryIndex.swift Tests/LibraryIndexSmoke.swift -o /tmp/nik-library-index-test
/tmp/nik-library-index-test
xcrun swiftc Native/Services/NiKHTTPDownload.swift Tests/DownloadCleanupSmoke.swift -o /tmp/nik-download-cleanup-test
/tmp/nik-download-cleanup-test
xcrun swiftc Native/Services/NiKHTTPDownload.swift Tests/HTTPDownloadSmoke.swift -o /tmp/nik-http-download-test
python3 Tests/http_download_test.py /tmp/nik-http-download-test
xcrun swiftc Native/Models/NiKAltSourceModels.swift Native/Services/NiKFileDigest.swift Native/Services/NiKHTTPDownload.swift Native/Services/NiKSourceDownloadService.swift Tests/SourceDownloadSmoke.swift -o /tmp/nik-source-download-test
python3 Tests/http_download_test.py /tmp/nik-source-download-test
xcrun swiftc Native/Models/NiKFileBrowserState.swift Tests/FileBrowserStateSmoke.swift -o /tmp/nik-file-browser-test
/tmp/nik-file-browser-test
xcrun swiftc Native/Models/NiKFileBrowserState.swift Native/Services/NiKFileDigest.swift Native/Models/NiKFileProperties.swift Tests/FilePropertiesSmoke.swift -o /tmp/nik-file-properties-test
/tmp/nik-file-properties-test
bash scripts/test-file-tools.sh
bash scripts/test-certificates.sh
bash scripts/build-ios.sh
python3 scripts/check-build-log.py build/build.log
mkdir -p "audit-results/pass${nik_audit_pass}"
cp dist/NiKSign-unsigned.ipa build/binary-info.txt "audit-results/pass${nik_audit_pass}/"
