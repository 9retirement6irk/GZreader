Test certificates for `tls_test.lua` (GZreader's certificate checks). Made once
with Python's `cryptography`; they're only for tests on this machine and name
example.com hosts only. `ca.crt` signs `good.crt` (api.example.com and
*.files.example.com, 2020–2120) and `expired.crt` (2020-01-01 to 2020-02-01);
`other-ca.crt` signs nothing here (a CA the server's certificate isn't from).
