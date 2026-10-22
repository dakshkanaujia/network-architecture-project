# BHP/1 — Binary HTTP Protocol (Network Architecture Project)

A from-scratch binary protocol (**BHP/1**) plus a file server and client that speak it, built using plain Python 3 standard-library sockets — no web framework, no third-party dependencies.

## Layout

```
src/protocol/frame.py    BHP/1 frame codec (shared by server & client)
src/server/bserve.py     File server
src/client/bcurl.py      Client
bserve, bcurl            Thin executable wrappers
www/                     Files bserve serves
tests/                   Unit test suite (protocol, bserve + bcurl)
examples/hexdump.txt     Annotated hexdump of one real request/response
SPEC.md                  The BHP/1 protocol specification
```

## Run the file server and client

```bash
./bserve ./www 9000
./bcurl -v localhost:9000/index.html
```

`bcurl` writes the response body to stdout, dumps both frames in hex
(with a field-by-field breakdown) to stderr when given `-v`, opens
exactly one TCP connection, and exits non-zero on a 4xx/5xx response:

```bash
./bcurl localhost:9000/does-not-exist.html; echo "exit=$?"   # exit=1
./bcurl localhost:9000/index.html;           echo "exit=$?"  # exit=0
```

The wire format is specified in [SPEC.md](SPEC.md); a real annotated
capture of one request/response pair is in
[examples/hexdump.txt](examples/hexdump.txt).

## Tests

```bash
python3 -m unittest discover -s tests -v
```

No external dependencies (pytest not required). Tests cover: basic requests,
frames split across multiple TCP reads, multiple frames in a single read,
malformed input (→400), missing resources (→404), unsupported methods (→405),
unknown BHP/1 frame types being skipped without disturbing the connection,
and the client's exit code on error responses.
