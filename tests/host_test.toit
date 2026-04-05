// Copyright (C) 2026 Toit contributors.
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the tests/TESTS_LICENSE file.

import expect show *
import host
import host.file

main:
  test-read-write
  test-read-write-bytes
  test-read-write-json
  test-read-write-yaml
  test-stat
  test-file-info-equality
  test-with-tmp-directory
  test-list-directory
  test-list-directory-full-path
  test-list-directory-block
  test-re-exports

test-read-write:
  host.with-tmp-directory "/tmp/host-test-": | dir |
    path := "$dir/test.txt"
    host.write path --data="Hello, World!"
    content := host.read path
    expect-equals "Hello, World!" content

test-read-write-bytes:
  host.with-tmp-directory "/tmp/host-test-": | dir |
    path := "$dir/test.bin"
    data := #[0x00, 0x01, 0x02, 0xFF]
    host.write path --data=data
    result := host.read --bytes path
    expect-equals data.size result.size
    data.size.repeat:
      expect-equals data[it] result[it]

test-read-write-json:
  host.with-tmp-directory "/tmp/host-test-": | dir |
    path := "$dir/test.json"
    obj := {
      "name": "toit",
      "version": 42,
      "tags": ["host", "file"],
    }
    host.write --json path --data=obj
    result := host.read --json path
    expect-equals "toit" result["name"]
    expect-equals 42 result["version"]
    expect-equals 2 result["tags"].size
    expect-equals "host" result["tags"][0]
    expect-equals "file" result["tags"][1]

test-read-write-yaml:
  host.with-tmp-directory "/tmp/host-test-": | dir |
    path := "$dir/test.yaml"
    obj := {
      "name": "toit",
      "count": 7,
    }
    host.write --yaml path --data=obj
    result := host.read --yaml path
    expect-equals "toit" result["name"]
    expect-equals 7 result["count"]

test-stat:
  host.with-tmp-directory "/tmp/host-test-": | dir |
    path := "$dir/test.txt"
    host.write path --data="hello"

    info := host.stat path
    expect-not-null info
    expect info.is-file
    expect (not info.is-directory)
    expect (not info.is-symlink)
    expect-equals 5 info.size
    expect info.modification-time <= Time.now
    expect info.modification-time > (Time.epoch --s=0)

    dir-info := host.stat dir
    expect-not-null dir-info
    expect dir-info.is-directory
    expect (not dir-info.is-file)

    missing := host.stat "$dir/nonexistent"
    expect-null missing

test-file-info-equality:
  host.with-tmp-directory "/tmp/host-test-": | dir |
    path := "$dir/test.txt"
    host.write path --data="hello"

    info1 := host.stat path
    info2 := host.stat path
    expect-equals info1 info2
    expect-equals info1.hash-code info2.hash-code

    path2 := "$dir/other.txt"
    host.write path2 --data="world"
    info3 := host.stat path2
    expect (info1 != info3)

    // Verify stringify works.
    str := info1.stringify
    expect (str.contains "file")
    expect (str.contains "size=5")

test-with-tmp-directory:
  captured-dir := null
  host.with-tmp-directory "/tmp/host-test-": | dir |
    captured-dir = dir
    expect (host.is-directory dir)
    host.write "$dir/file.txt" --data="data"
  // Directory should be cleaned up.
  expect (not (host.is-directory captured-dir))

test-list-directory:
  host.with-tmp-directory "/tmp/host-test-": | dir |
    host.write "$dir/a.txt" --data="a"
    host.write "$dir/b.txt" --data="b"
    host.mkdir "$dir/sub"

    entries := host.list-directory dir
    expect-equals 3 entries.size
    expect (entries.contains "a.txt")
    expect (entries.contains "b.txt")
    expect (entries.contains "sub")

test-list-directory-full-path:
  host.with-tmp-directory "/tmp/host-test-": | dir |
    host.write "$dir/file.txt" --data="data"

    entries := host.list-directory --full-path dir
    expect-equals 1 entries.size
    expect-equals "$dir/file.txt" entries[0]

test-list-directory-block:
  host.with-tmp-directory "/tmp/host-test-": | dir |
    host.write "$dir/a.txt" --data="a"
    host.write "$dir/b.txt" --data="b"

    collected := []
    host.list-directory dir: | entry |
      collected.add entry
    expect-equals 2 collected.size
    expect (collected.contains "a.txt")
    expect (collected.contains "b.txt")

test-re-exports:
  // Verify that re-exported functions and classes are accessible.
  // We just check they exist and are callable — the underlying
  // functionality is tested by the module-specific tests.

  expect (host.env is host.EnvironmentVariableMap)

  host.with-tmp-directory "/tmp/host-test-": | dir |
    // File operations.
    path := "$dir/test.txt"
    host.write path --data="hello"
    expect (host.is-file path)
    expect (not (host.is-directory path))
    host.delete path
    expect (not (host.is-file path))

    // Directory operations.
    sub := "$dir/sub"
    host.mkdir sub
    expect (host.is-directory sub)
    host.rmdir sub

    // Stream.
    stream := host.Stream.for-write "$dir/stream.txt"
    stream.out.write "test"
    stream.close

    // cwd and realpath.
    expect-not-null host.cwd
    rp := host.realpath dir
    expect-not-null rp

    // SEPARATOR.
    expect (host.SEPARATOR == "/" or host.SEPARATOR == "\\")
