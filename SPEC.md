# BHP/1 — Binary HTTP Protocol, version 1

*A stranger who has never seen the implementation should be able to build
an independent, interoperable client or server from this document alone.*

## 1. Overview

BHP/1 is a minimal binary request/response protocol for fetching files
from a server, carried over a single persistent TCP connection. It
solves the same problem HTTP/1.1 solves — "ask for a resource, get
back a status, headers and bytes" — but frames every message with an
explicit length instead of textual delimiters, so a receiver never has
to guess where a message ends.

## 2. Transport

BHP/1 runs over TCP. A client opens **exactly one** TCP connection to
the server and reuses it for every request it sends; it never opens a
second connection to the same server mid-session. A connection carries
a sequence of frames in both directions and stays open until either
side closes the socket — there is no per-request handshake or teardown.

## 3. Frame format

Every message, in either direction, is a **frame**: an 8-byte fixed
header followed by a payload whose length the header states exactly.
All multi-byte integers are big-endian.

```
Offset | Size | Field
-------|------|--------------------------------------------
0      | 1    | Version          (must be 1)
1      | 1    | Type             (0x01 REQUEST, 0x02 RESPONSE)
2      | 1    | Flags            (reserved, must be 0)
3      | 1    | Reserved         (must be 0)
4      | 4    | Payload Length N (uint32, big-endian)
8      | N    | Payload
```

The fixed header is deliberately **type-agnostic**: "how many bytes
does this frame occupy" depends only on the Length field, never on
understanding the payload. A receiver always reads exactly `8 + N`
bytes for one frame, whether or not it recognises `Type` or can parse
`Payload`. This one property is what makes the rest of the protocol
robust: a malformed payload can never desynchronise the stream, and a
frame type invented by a future version 2 can be skipped by a version
1 receiver without corrupting anything that follows it.

`Version`/`Flags`/`Reserved` are fixed at 1/0/0 in this version and
exist purely so a future revision has somewhere to put a capability
bit or a second version without changing the header's size.

## 4. Frame types

- **0x01 REQUEST** — client → server, described in §5.
- **0x02 RESPONSE** — server → client, described in §6.
- **Anything else** — reserved for future protocol versions. A
  compliant receiver of any age MUST NOT reject or error on an
  unrecognised `Type`; see §9.

## 5. Request format (payload of a REQUEST frame)

```
Offset | Size | Field
-------|------|--------------------------------------------
0      | 1    | Method id
1      | 2    | Path length P (uint16)
3      | P    | Path (UTF-8, e.g. "/index.html")
3+P    | 1    | Header count H
...    | ...  | H header entries (§7)
...    | rest | Body (0 bytes for GET/HEAD)
```

Method ids: `1=GET, 2=HEAD, 3=POST, 4=PUT, 5=DELETE`. A server that
does not support a given method for a given resource replies `405`
(§8); an unrecognised method id is a malformed request and gets `400`.

## 6. Response format (payload of a RESPONSE frame)

```
Offset | Size | Field
-------|------|--------------------------------------------
0      | 2    | Status code (uint16, e.g. 200, 404)
2      | 1    | Header count H
3      | ...  | H header entries (§7)
...    | rest | Body
```

## 7. Header encoding

Ten header names that appear on nearly every message get a 1-byte
static id instead of paying for their name bytes on the wire every
time (the same idea HPACK uses, reduced to the ten names this
protocol actually needs):

```
id | name             id | name
---|------------------ --|------------------
1  | Host             6  | Date
2  | Content-Type      7  | Content-Encoding
3  | Content-Length    8  | Accept
4  | Connection        9  | User-Agent
5  | Server           10  | Location
```

Each header entry is:

```
Size | Field
-----|-------------------------------------------------
1    | Name id (1-10 = static table; 0 = literal name follows)
     |   if 0: [1 byte name length][name bytes, UTF-8]
2    | Value length (uint16)
...  | Value bytes (UTF-8)
```

Any header name outside the static table is sent with id `0` and an
explicit length-prefixed name — the protocol is not limited to ten
headers, only the ten most common ones are cheap.

## 8. Status / error semantics

- **200** — request understood, resource found, body follows.
- **400 Bad Request** — the frame's envelope was fine (Length was
  honoured) but its payload was structurally invalid: a length field
  pointing past the end of the payload, an unknown static header id,
  a path that escapes the server root, an unrecognised method id, or
  a RESPONSE frame received where a REQUEST was expected.
- **404 Not Found** — a syntactically valid GET/HEAD for a path that
  does not map to a file under the server's root.
- **405 Method Not Allowed** — a syntactically valid request whose
  method the server does not implement (this server implements only
  GET and HEAD).

A response's body is empty for non-200 statuses in this
implementation; nothing in the frame format requires that.

## 9. Unknown frame types

A receiver that reads a frame header with a `Type` it does not
recognise MUST still read exactly `Length` payload bytes (discarding
them) and then continue reading the next frame from the same
connection, exactly as if the frame had never arrived. It MUST NOT
close the connection, MUST NOT send an error response for that frame,
and MUST NOT attempt to interpret the payload. This is what lets a
version 2 of this protocol introduce new frame types (e.g. a PING, or
a multi-frame streamed body) that a version 1 peer can safely ignore.

## 10. Connection lifecycle

A connection begins with a TCP handshake and stays open across an
arbitrary number of frames in each direction. The server processes
frames from one connection strictly in arrival order and sends exactly
one RESPONSE frame for each REQUEST frame it accepts (it sends nothing
for a skipped unknown frame type, per §9). The connection ends only
when a peer closes its socket (or, in `bserve`'s case, after an idle
timeout with no frames). Nothing in the protocol requires a client to
wait for one response before sending the next request, but this
project's client (`bcurl`) sends one request and waits for its
response before exiting, by design (§"client" below).

## 11. Worked example

See `examples/hexdump.txt` for a complete, real, annotated capture of
one REQUEST frame (`GET /index.html`) and its RESPONSE frame, byte by
byte, generated by running `bserve`/`bcurl` against each other.
