// Copyright (C) 2023 Toitware ApS.
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the tests/TESTS_LICENSE file.

// Helper program for tests, because echo and the shell are not available everywhere.

import host.os

// Expands environment variables in the arguments, using $ syntax.
main args:
  print
      (args.map: expand it).join " "

// Expands a string like 'Hello $USER, and their friends' by replacing '$USER'
//   with the value of the environment variable.  A double dollar is replaced
//   with a single literal dollar sign.
expand src -> string:
  expand := false
  result := []
  src.split "\$": | part |
    if not expand:
      result.add part
      expand = true
    else if part == "":  // Double dollar detected: Replace with a literal $.
      result.add "\$"
      expand = false
    else:
      var := part
      rest := ""
      close := part.index-of ")"
      if part[0] == '(' and close != -1:
        var = part[1..close]
        rest = part[close + 1 ..]
      else:
        for i := 0; i < part.size; i++:
          c := part[i]
          if not is-identifier c:
            var = part[0..i]
            rest = part[i..]
            break
      value := os.env.get var
      if value: result.add value
      result.add rest
  return result.join ""

is-identifier c/int  -> bool:
  if 'a' <= c <= 'z': return true
  if 'A' <= c <= 'Z': return true
  if c == '_': return true
  return '0' <= c <= '9'
