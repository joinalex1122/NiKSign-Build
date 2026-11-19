#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
cert_test_dir=$(mktemp -d)
trap 'rm -rf "$cert_test_dir"' EXIT
mkdir -p "$cert_test_dir/Sources" "$cert_test_dir/fixtures"
cp Tests/Certificates/Package.swift "$cert_test_dir/Package.swift"
cp -R Tests/Certificates/OpenSSL "$cert_test_dir/OpenSSL"
cp Tests/Certificates/main.swift Native/Dependencies/NiKCertificateStore.swift Native/Dependencies/NiKLocalTLSIdentity.swift Native/Services/NiKTLSServerCertificate.swift Native/Dependencies/NiKOTAProfile.swift Native/Models/NiKRevocationSchedule.swift Native/Models/NiKCertificateModels.swift Native/Models/NiKPlistValue.swift Native/Services/NiKCertificateRevocation.swift Native/Services/NiKProvisioningValidation.swift Native/Models/NiKProvisioningPattern.swift Tests/Support/NiKProvisionFixture.swift "$cert_test_dir/Sources/"
cert_openssl="$(brew --prefix openssl@3)/bin/openssl"
"$cert_openssl" req -x509 -newkey rsa:2048 -noenc -keyout "$cert_test_dir/fixtures/key.pem" -out "$cert_test_dir/fixtures/cert.pem" -days 1 -subj '/CN=NiKSign Synthetic Test' 2>/dev/null
"$cert_openssl" pkcs12 -export -inkey "$cert_test_dir/fixtures/key.pem" -in "$cert_test_dir/fixtures/cert.pem" -out "$cert_test_dir/fixtures/modern.p12" -passout 'pass: test password '
"$cert_openssl" pkcs12 -export -legacy -inkey "$cert_test_dir/fixtures/key.pem" -in "$cert_test_dir/fixtures/cert.pem" -out "$cert_test_dir/fixtures/legacy.p12" -passout 'pass: test password '
"$cert_openssl" version
NIK_TEST_OPENSSL="$cert_openssl" PKG_CONFIG_PATH="$(brew --prefix openssl@3)/lib/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}" swift run --package-path "$cert_test_dir" CertificateSmoke "$cert_test_dir/fixtures"
"$cert_openssl" x509 -inform DER -in "$cert_test_dir/fixtures/local-ota.cer" -out "$cert_test_dir/fixtures/local-ota.pem"
"$cert_openssl" verify -CAfile "$cert_test_dir/fixtures/local-ota.pem" "$cert_test_dir/fixtures/local-ota.pem"

"$cert_openssl" x509 -inform DER -in "$cert_test_dir/fixtures/local-server.cer" -out "$cert_test_dir/fixtures/local-server.pem"
"$cert_openssl" verify -CAfile "$cert_test_dir/fixtures/local-ota.pem" -verify_ip 127.0.0.1 -purpose sslserver "$cert_test_dir/fixtures/local-server.pem"

python3 - "$cert_test_dir/fixtures" "$cert_openssl" <<'PYTLS'
from pathlib import Path
import subprocess,sys,ssl
root=Path(sys.argv[1]);cli=sys.argv[2]
ca=subprocess.check_output([cli,'x509','-in',str(root/'local-ota.pem'),'-noout','-text'],text=True)
assert 'CA:TRUE' in ca and 'Certificate Sign, CRL Sign' in ca and '2048 bit' in ca and 'sha256WithRSAEncryption' in ca
leaf=subprocess.check_output([cli,'x509','-in',str(root/'local-server.pem'),'-noout','-text'],text=True)
assert 'CA:FALSE' in leaf and 'TLS Web Server Authentication' in leaf and 'IP Address:127.0.0.1' in leaf and 'DNS:localhost' in leaf
assert '2048 bit' in leaf and 'sha256WithRSAEncryption' in leaf
dates=subprocess.check_output([cli,'x509','-in',str(root/'local-server.pem'),'-noout','-dates'],text=True).splitlines()
a,b=[ssl.cert_time_to_seconds(x.split('=',1)[1]) for x in dates]
assert 0 < b-a <= 825*86400
print('PASS: production CA/leaf RSA2048 SHA256, CA constraints/key usages, leaf SAN/EKU and <=825-day validity')
PYTLS
