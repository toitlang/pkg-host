// Copyright (C) 2019 Toitware ApS.
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the tests/TESTS_LICENSE file.

import expect show *
import host.pipe
import io
import monitor
import semver

class Stress:
  executable ::= ?

  constructor .executable:

  run-compiler id channel:
    channel.send "$id: started"
    pipes := pipe.fork
        true                // use_path
        pipe.PIPE-CREATED   // stdin
        pipe.PIPE-CREATED   // stdout
        pipe.PIPE-INHERITED // stderr
        executable
        [
          executable,
        ]
    to/pipe.OpenPipe   := pipes[0]
    from/pipe.OpenPipe := pipes[1]
    pid  := pipes[3]
    pipe.dont-wait-for pid
    channel.send "$id: forked"

    pipe-writer := to.out
    // Stress pipes.
    LINES-COUNT ::= 500
    for i := 0; i < LINES-COUNT; i++:
      pipe-writer.write "line$i\n"
    pipe-writer.close

    reader := from.in
    read-counter := 0
    while true:
      line := reader.read-line
      if line == null:
        channel.send "$id: done"
        break
      expect-equals "line$read-counter" line
      read-counter++
    expect-equals LINES-COUNT read-counter
    from.close
    channel.send null

logs := []

main:
  stress := Stress "cat"

  now-us := Time.monotonic-us
  counter := 0
  while Time.monotonic-us - now-us < 15_000_000:
    print "Iteration $(counter++)"
    logs.clear
    channel := monitor.Channel 100
    running := 0
    for i := 0; i < 30; i++:
      running++
      task:: stress.run-compiler i channel
    while true:
      value := channel.receive
      if value == null:
        running--
        if running == 0: break
      else:
        // log value
        logs.add value
  print "time's up"
