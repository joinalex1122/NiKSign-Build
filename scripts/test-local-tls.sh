#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
tls_test_dir=$(mktemp -d)
trap 'rm -rf "$tls_test_dir"' EXIT
if [[ $(uname) == Darwin ]]; then
    tls_openssl="$(brew --prefix openssl@3)/bin/openssl"
    tls_flags=(-I "$(brew --prefix openssl@3)/include" -L "$(brew --prefix openssl@3)/lib")
else
    tls_openssl=openssl
    tls_flags=()
fi
"$tls_openssl" req -x509 -newkey rsa:2048 -noenc -keyout "$tls_test_dir/ca-key.pem" -out "$tls_test_dir/ca.pem" -days 2 -subj '/CN=localhost' -addext 'basicConstraints=critical,CA:TRUE' -addext 'keyUsage=critical,keyCertSign,digitalSignature' 2>/dev/null
"$tls_openssl" pkcs12 -export -inkey "$tls_test_dir/ca-key.pem" -in "$tls_test_dir/ca.pem" -out "$tls_test_dir/ca.p12" -passout pass:test-ca
"$tls_openssl" req -x509 -newkey rsa:2048 -noenc -keyout "$tls_test_dir/not-ca-key.pem" -out "$tls_test_dir/not-ca.pem" -days 1 -subj '/CN=Not a CA' -addext 'basicConstraints=critical,CA:FALSE' 2>/dev/null
"$tls_openssl" pkcs12 -export -inkey "$tls_test_dir/not-ca-key.pem" -in "$tls_test_dir/not-ca.pem" -out "$tls_test_dir/not-ca.p12" -passout pass:test-ca
swiftc -I Tests/Certificates/OpenSSL "${tls_flags[@]}" Native/Services/NiKTLSServerCertificate.swift Tests/TLSServerCertificateSmoke.swift -o "$tls_test_dir/test"
"$tls_test_dir/test" "$tls_test_dir"
"$tls_openssl" x509 -inform DER -in "$tls_test_dir/leaf.cer" -out "$tls_test_dir/leaf.pem"
"$tls_openssl" verify -x509_strict -CAfile "$tls_test_dir/ca.pem" -verify_ip 127.0.0.1 -purpose sslserver "$tls_test_dir/leaf.pem"
"$tls_openssl" verify -x509_strict -CAfile "$tls_test_dir/ca.pem" -verify_hostname localhost -purpose sslserver "$tls_test_dir/leaf.pem"
if "$tls_openssl" verify -CAfile "$tls_test_dir/ca.pem" -verify_hostname example.com -purpose sslserver "$tls_test_dir/leaf.pem" >/dev/null 2>&1; then
    echo 'FAIL: wrong hostname accepted'; exit 1
fi
if "$tls_openssl" verify -CAfile "$tls_test_dir/not-ca.pem" -verify_ip 127.0.0.1 "$tls_test_dir/leaf.pem" >/dev/null 2>&1; then
    echo 'FAIL: unrelated root accepted'; exit 1
fi
"$tls_openssl" pkcs12 -in "$tls_test_dir/leaf.p12" -passin "file:$tls_test_dir/leaf-password" -nokeys -out "$tls_test_dir/chain.pem"
python3 - "$tls_test_dir" "$tls_openssl" <<'PY'
import pathlib, subprocess, sys, ssl
root = pathlib.Path(sys.argv[1])
assert (root/'chain.pem').read_text().count('BEGIN CERTIFICATE') == 2
text = subprocess.check_output([sys.argv[2], 'x509', '-in', str(root/'leaf.pem'), '-noout', '-text'], text=True)
assert 'CA:FALSE' in text and 'TLS Web Server Authentication' in text
assert 'Subject Key Identifier' in text and 'Authority Key Identifier' in text
assert '2048 bit' in text and 'sha256WithRSAEncryption' in text
dates=subprocess.check_output([sys.argv[2], 'x509', '-in', str(root/'leaf.pem'), '-noout', '-dates'],text=True).splitlines()
a,b=[ssl.cert_time_to_seconds(x.split('=',1)[1]) for x in dates]
assert 0 < b-a <= 825*86400
assert 'DNS:localhost' in text and 'IP Address:127.0.0.1' in text
print('PASS: actual server CA chain, SAN/EKU/basic constraints, unrelated root and wrong-host rejection')
PY
