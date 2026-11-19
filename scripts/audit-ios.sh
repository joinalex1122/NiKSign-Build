#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
nik_audit_label=${1:-build}
case "$nik_audit_label" in build|pass1|pass2) ;; *) exit 2 ;; esac
# These are ignored generated products, never application input or user documents.
rm -rf build NiKSign.xcodeproj
python3 scripts/check-integration.py
python3 scripts/check-dependencies.py
bash scripts/test-loopback-ota.sh
python3 Tests/minizip_test.py
python3 Tests/verify_ipa_test.py
python3 Tests/zsign_provisioning_test.py
python3 Tests/zsign_cms_test.py
xcrun swiftc Native/Models/NiKPlistValue.swift Native/Models/NiKCertificateModels.swift Native/Models/NiKRevocationSchedule.swift Tests/RevocationScheduleSmoke.swift -o /tmp/nik-revocation-schedule-test
/tmp/nik-revocation-schedule-test
xcrun swiftc Native/Models/NiKOTAURLs.swift Native/Models/NiKOTALandingPage.swift Tests/OTAURLsSmoke.swift -o /tmp/nik-ota-urls-test
/tmp/nik-ota-urls-test
xcrun swiftc Native/Services/NiKPathValidator.swift Tests/PathValidatorSmoke.swift -o /tmp/nik-path-test
/tmp/nik-path-test
xcrun swiftc Native/NiKFileImport.swift Tests/FileImportSmoke.swift -o /tmp/nik-file-import-test
/tmp/nik-file-import-test
xcrun swiftc Native/Models/NiKSigningModels.swift Native/Models/NiKSigningJob.swift Tests/SigningJobsSmoke.swift -o /tmp/nik-signing-jobs-test
xcrun swiftc Native/Models/NiKSigningModels.swift Native/Models/NiKSigningJob.swift Native/Models/NiKLibraryItem.swift Native/Services/NiKFileMutationReservations.swift Native/Services/NiKSigningQueue.swift Tests/QueueRemovalSmoke.swift -o /tmp/nik-queue-removal-test
/tmp/nik-queue-removal-test
xcrun swiftc Native/Models/NiKPlistValue.swift Native/Models/NiKCertificateModels.swift Native/Models/NiKCertificateCompatibility.swift Native/Models/NiKProvisioningPattern.swift Tests/CertificateCompatibilitySmoke.swift -o /tmp/nik-cert-compat-test
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
xcrun swiftc Native/Services/NiKFileMutationReservations.swift Tests/FileMutationReservationsSmoke.swift -o /tmp/nik-file-mutation-test
/tmp/nik-file-mutation-test
xcrun swiftc Native/Models/NiKSigningModels.swift Native/Models/NiKLibraryItem.swift Native/Services/NiKLibraryIndex.swift Native/Models/NiKFileBrowserState.swift Native/Models/NiKTrashRecord.swift Native/Services/NiKTrashStore.swift Tests/TrashStoreSmoke.swift -o /tmp/nik-trash-store-test
/tmp/nik-trash-store-test
xcrun swiftc Native/Models/NiKSigningModels.swift Native/Models/NiKLibraryItem.swift Native/Services/NiKLibraryIndex.swift Native/Models/NiKFileBrowserState.swift Native/Models/NiKTrashRecord.swift Native/Services/NiKTrashStore.swift Native/Services/NiKTrashLibraryTransaction.swift Tests/TrashLibraryTransactionSmoke.swift -o /tmp/nik-trash-library-test
/tmp/nik-trash-library-test
xcrun swiftc Native/Models/NiKFileRecoveryRecord.swift Native/Models/NiKPlistValue.swift Native/Models/NiKTypedPlistDocument.swift Tests/TypedPlistSmoke.swift -o /tmp/nik-typed-plist-test
/tmp/nik-typed-plist-test
xcrun swiftc Native/Models/NiKFileRecoveryRecord.swift Native/Models/NiKPlistValue.swift Native/Models/NiKTypedPlistDocument.swift Native/Models/NiKPlistValueDraft.swift Tests/PlistValueDraftSmoke.swift -o /tmp/nik-plist-draft-test
/tmp/nik-plist-draft-test
xcrun swiftc Native/Services/NiKSignedFileAccess.swift Tests/SignedFileAccessSmoke.swift -o /tmp/nik-signed-file-test
/tmp/nik-signed-file-test
bash scripts/test-file-tools.sh
bash scripts/test-local-tls.sh
bash scripts/test-https-ota.sh
bash scripts/test-certificates.sh
bash scripts/build-ios.sh
python3 scripts/check-build-log.py build/build.log
mkdir -p "audit-results/${nik_audit_label}"
cp dist/NiKSign-unsigned.ipa build/binary-info.txt "audit-results/${nik_audit_label}/"
