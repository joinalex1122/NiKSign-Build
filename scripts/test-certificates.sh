#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
cert_test_dir=$(mktemp -d)
trap 'rm -rf "$cert_test_dir"' EXIT
mkdir -p "$cert_test_dir/Sources" "$cert_test_dir/fixtures"
cp Tests/Certificates/Package.swift "$cert_test_dir/Package.swift"
cp Tests/Certificates/main.swift Native/Dependencies/NiKCertificateStore.swift "$cert_test_dir/Sources/"
cert_openssl="$(brew --prefix openssl@3)/bin/openssl"
"$cert_openssl" req -x509 -newkey rsa:2048 -noenc -keyout "$cert_test_dir/fixtures/key.pem" -out "$cert_test_dir/fixtures/cert.pem" -days 1 -subj '/CN=NiKSign Synthetic Test' 2>/dev/null
"$cert_openssl" pkcs12 -export -inkey "$cert_test_dir/fixtures/key.pem" -in "$cert_test_dir/fixtures/cert.pem" -out "$cert_test_dir/fixtures/modern.p12" -passout 'pass: test password '
"$cert_openssl" pkcs12 -export -legacy -inkey "$cert_test_dir/fixtures/key.pem" -in "$cert_test_dir/fixtures/cert.pem" -out "$cert_test_dir/fixtures/legacy.p12" -passout 'pass: test password '
swift run --package-path "$cert_test_dir" CertificateSmoke "$cert_test_dir/fixtures"
