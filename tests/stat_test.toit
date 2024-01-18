// Copyright (C) 2023 Toitware ApS.
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the tests/TESTS_LICENSE file.

import expect show *

import host.file
import writer show Writer

main:
  s := file.stat "/etc"
  if s:
    m-time := s[file.ST-MTIME]
    print m-time
    expect m-time < Time.now
    expect m-time > (Time.epoch --s=0)
