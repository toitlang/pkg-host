// Copyright (C) 2023 Toitware ApS.
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the tests/TESTS_LICENSE file.

import expect show *

import host.file
import writer show Writer

main:
  s := file.stat "/etc"
  if s:
    m_time := s[file.ST_MTIME]
    print m_time
    expect m_time < Time.now
    expect m_time > (Time.epoch --s=0)
