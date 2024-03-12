// Copyright (C) 2018 Toitware ApS.
// Use of this source code is governed by an MIT-style license that can be
// found in the package's LICENSE file.

import bytes
import .file as file
import io
import monitor
import reader as old-reader
import system as sdk-system

process-resource-group_ ::= process-init_
pipe-resource-group_ ::= pipe-init_
standard-pipes_ ::= [ null, null, null ]

// Keep in sync with similar list in event_sources/subprocess.cc.
PROCESS-EXITED_ ::= 1
PROCESS-SIGNALLED_ ::= 2
PROCESS-EXIT-CODE-SHIFT_ ::= 2
PROCESS-EXIT-CODE-MASK_ ::= 0xff
PROCESS-SIGNAL-SHIFT_ ::= 10
PROCESS-SIGNAL-MASK_ ::= 0xff

READ-EVENT_ ::= 1 << 0
WRITE-EVENT_ ::= 1 << 1
CLOSE-EVENT_ ::= 1 << 2
ERROR-EVENT_ ::= 1 << 3

UNKNOWN-DIRECTION_ ::= 0
PARENT-TO-CHILD_ ::= 1
CHILD-TO-PARENT_ ::= 2


get-standard-pipe_ fd/int:
  if not standard-pipes_[fd]:
    if file.is-open-file_ fd:
      standard-pipes_[fd] = file.Stream.internal_ fd  // TODO: This is a private constructor.
    else:
      standard-pipes_[fd] = OpenPipe.from-std_ (fd-to-pipe_ pipe-resource-group_ fd)
  return standard-pipes_[fd]

/**
A program may be executed with an open file descriptor.  This is similar
  to the technique used by the shell to launch programs with their stdin,
  stdout and stderr attached to pipes or files.  Given the number of
  the file descriptor this function will return a $old-reader.Reader or writer
  object.  You are expected to know which direction the file descriptor has.
*/
get-numbered-pipe fd/int:
  if fd < 0: throw "OUT_OF_RANGE"
  if fd <= 2: throw "Use stdin, stdout, stderr"
  if file.is-open-file_ fd:
    return file.Stream.internal_ fd  // TODO: This is a private constructor.
  else:
    return OpenPipe.from-std_ (fd-to-pipe_ pipe-resource-group_ fd)

class OpenPipe extends Object with io.InMixin io.OutMixin implements old-reader.Reader:
  resource_ := ?
  state_ := ?
  pid := null
  child-process-name_ /string?
  input_ /int := UNKNOWN-DIRECTION_

  fd := -1  // Other end of descriptor, for child process.

  constructor input/bool --child-process-name="child process":
    group := pipe-resource-group_
    pipe-pair := create-pipe_ group input
    input_ = input ? PARENT-TO-CHILD_ : CHILD-TO-PARENT_
    child-process-name_ = child-process-name
    resource_ = pipe-pair[0]
    fd = pipe-pair[1]
    state_ = monitor.ResourceState_ pipe-resource-group_ resource_

  constructor.from-std_ .resource_:
    group := pipe-resource-group_
    child-process-name_ = null
    state_ = monitor.ResourceState_ pipe-resource-group_ resource_

  /**
  Deprecated. Use 'read' on $in instead.
  */
  read -> ByteArray?:
    return in.read

  consume_ -> ByteArray?:
    if input_ == PARENT-TO-CHILD_:
      throw "read from an output pipe"
    while true:
      state_.wait-for-state READ-EVENT_ | CLOSE-EVENT_
      result := read_ resource_
      if result != -1:
        if result == null:
          try:
            check-exit_ pid child-process-name_
          finally:
            pid = null
        return result
      state_.clear-state READ-EVENT_

  /**
  Deprecated. Use 'write' or 'try-write' on $out instead.
  */
  write x from = 0 to = x.size:
    return try-write_ x from to

  try-write_ data/io.Data from/int to/int -> int:
    if input_ == CHILD-TO-PARENT_:
      throw "write to an input pipe"
    state_.wait-for-state WRITE-EVENT_ | ERROR-EVENT_
    bytes-written := write-primitive_ resource_ data from to
    if bytes-written == 0: state_.clear-state WRITE-EVENT_
    return bytes-written

  close:
    close_ resource_
    if state_:
      state_.dispose
      state_ = null
    if input_ == PARENT-TO-CHILD_:
      check-exit_ pid child-process-name_

  is-a-terminal -> bool:
    return is-a-tty_ resource_

check-exit_ pid child-process-name/string? -> none:
  if child-process-name == null:
    child-process-name = "child process"
  if pid:
    exit-value := wait-for pid
    if (exit-value & PROCESS-SIGNALLED_) != 0:
      // Process crashed.
      throw
        "$child-process-name: " +
          signal-to-string (exit-signal exit-value)
    code := exit-code exit-value
    if code != 0:
      throw "$child-process-name: exited with status $code"

pipe-fd_ resource:
  #primitive.pipe.fd

pipe-init_:
  #primitive.pipe.init

create-pipe_ resource-group input/bool:
  #primitive.pipe.create-pipe

write-primitive_ pipe data/io.Data from to:
  #primitive.pipe.write: | error |
    written := 0
    io.primitive-redo-chunked-io-data_ error data from to: | chunk/ByteArray |
      chunk-written := write_primitive_ pipe chunk 0 chunk.size
      written += chunk-written
      if chunk-written < chunk.size: return written
    return written

read_ pipe:
  #primitive.pipe.read

close_ pipe:
  return close_ pipe pipe-resource-group_

close_ pipe resource-group:
  #primitive.pipe.close

/// Use the stdin/stdout/stderr that the parent Toit process has.
PIPE-INHERITED ::= -1
/// Create new pipe and return it.
PIPE-CREATED ::= -2

create-pipe-helper_ input-flag index result:
  pipe-ends := OpenPipe input-flag
  result[index] = pipe-ends
  return pipe-ends.fd

/**
Forks a process.
Attaches the given pipes to the stdin, stdout and stderr
  of the new process.  Pipe arguments can be an open file descriptor from the
  file module or a pipe resource from this pipe module or one of the PIPE_
  constants above.
Returns an array with [stdin, stdout, stderr, child process].
To avoid zombies you must either give the child process to either
  `dont_wait_for` or `wait_for`.
Optionally you can pass pipes that should be passed to the
  child process as open file descriptors 3 and/or 4.
Optionally, $environment variables can be passed as a map.
  Keys in the map should be strings, and values should be strings or null,
  where null indicates that the variable should be unset in the child
  process.
Note that if you override the PATH environment variable, but set the $use-path
  flag, the new value of PATH will be used to find the executable.
*/
fork use-path stdin stdout stderr command arguments -> List
    --environment/Map?=null
    --file-descriptor-3/OpenPipe?=null
    --file-descriptor-4/OpenPipe?=null:
  if sdk-system.platform == sdk-system.PLATFORM-WINDOWS:
    arguments = arguments.map: windows-escape_ it
  result := List 4
  flat-environment := environment ? (Array_ environment.size * 2) : null
  index := 0
  if environment: environment.do: | key value |
    flat-environment[index++] = key.stringify
    flat-environment[index++] = (value == null) ? null : value.stringify
  exception := catch:
    if stdin == PIPE-CREATED:
      stdin = create-pipe-helper_ true 0 result
    if stdout == PIPE-CREATED:
      stdout = create-pipe-helper_ false 1 result
    if stderr == PIPE-CREATED:
      stderr = create-pipe-helper_ false 2 result
    fd-3 := file-descriptor-3 ? file-descriptor-3.fd : -1
    fd-4 := file-descriptor-4 ? file-descriptor-4.fd : -1
    result[3] = fork_ process-resource-group_ use-path stdin stdout stderr fd-3 fd-4 command (Array_.ensure arguments) flat-environment
  if exception:
    // If an exception is thrown we end up here.  If the fork succeeded then
    // the pipes would be closed.  Here we have an error and need to close
    // the pipes that we opened automatically, while leaving others open for
    // a retry.
    if result[0]:
      result[0].close
      file.close_ stdin
    if result[1]:
      result[1].close
      file.close_ stdout
    if result[2]:
      result[2].close
      file.close_ stderr
    if (command.index-of " ") != -1:
      throw "Error trying to run executable (arguments appended to filename?): '$command': $exception"
    else:
      clarification := ""
      if command.size > 0 and command[0] != '/':
        clarification = use-path ? " using \$PATH" : " not using path"
      throw "Error trying to run '$command'$clarification: $exception"
  return result

windows-escape_ path/string -> string:
  if (path.index-of " ") < 0
      and (path.index-of "\t") < 0
      and (path.index-of "\"") < 0:
    return path
  // The path contains spaces or quotes, so we have to escape.
  // Make the buffer a little larger than the path in the hope that we don't
  // have to grow it while building.
  accumulator := bytes.Buffer.with-initial-size (path.size + 4 + (path.size >> 2))
  accumulator.write-byte '"'  // Initial double quote.
  backslashes := 0
  path.size.repeat:
    byte := path.at --raw it
    if byte == '"':
      // Literal double quote.  Precede with an odd number of backslashes.
      (backslashes * 2 + 1).repeat: accumulator.write-byte '\\'
      backslashes = 0
      accumulator.write-byte '"'
    else if byte == '\\':
      // A single backslash in the input.
      backslashes++
    else:
      // Backslashes do not need to be doubled when they do not precede a double quote.
      backslashes.repeat: accumulator.write-byte '\\'
      backslashes = 0
      accumulator.write-byte byte
  // If there are unoutput backslashes at the end we need to double them.
  (backslashes * 2).repeat: accumulator.write-byte '\\'
  accumulator.write-byte '"'  // Final double quote.
  return accumulator.bytes.to-string

/// Variant of $(to arguments).
to --environment/Map?=null command arg1 -> OpenPipe:
  return to --environment=environment [command, arg1]

/// Variant of $(to arguments).
to --environment/Map?=null command arg1 arg2 -> OpenPipe:
  return to --environment=environment [command, arg1, arg2]

/// Variant of $(to arguments).
to --environment/Map?=null command arg1 arg2 arg3 -> OpenPipe:
  return to --environment=environment [command, arg1, arg2, arg3]

/// Variant of $(to arguments).
to --environment/Map?=null command arg1 arg2 arg3 arg4 -> OpenPipe:
  return to --environment=environment [command, arg1, arg2, arg3, arg4]

/**
Forks a program, and returns its stdin pipe.
Uses PATH to find the program.
Can be passed either a command (with no arguments) as a string, or an array
  of arguments, where the 0th argument is the command.
The user of this function is expected to eventually call close on the writer,
  otherwise the child process will be left running.
The child process is expected to exit when its stdin is closed.
The close method on the returned writer will throw an exception if the
  child process crashes or exits with a non-zero exit code.
The $environment argument is used as in $fork.
*/
to --environment/Map?=null arguments -> OpenPipe:
  if arguments is string:
    return to [arguments]
  pipe-ends := OpenPipe true --child-process-name=arguments[0]
  stdin := pipe-ends.fd
  pipes := fork --environment=environment true stdin PIPE-INHERITED PIPE-INHERITED arguments[0] arguments
  pipe-ends.pid = pipes[3]
  return pipe-ends

/// Variant of $(from arguments).
from --environment/Map?=null command arg1 -> OpenPipe:
  return from --environment=environment [command, arg1]

/// Variant of $(from arguments).
from --environment/Map?=null command arg1 arg2 -> OpenPipe:
  return from --environment=environment [command, arg1, arg2]

/// Variant of $(from arguments).
from --environment/Map?=null command arg1 arg2 arg3 -> OpenPipe:
  return from --environment=environment [command, arg1, arg2, arg3]

/// Variant of $(from arguments).
from --environment/Map?=null command arg1 arg2 arg3 arg4 -> OpenPipe:
  return from --environment=environment [command, arg1, arg2, arg3, arg4]

/**
Forks a program, and return its stdout pipe.
Uses PATH to find the program.
Can be passed either a command (with no arguments) as a string, or an array
  of arguments, where the 0th argument is the command.
The user of this function is expected to read the returned reader
  until it returns null (end of file), otherwise process zombies will
  be left around.  The end of file value is not returned from read
  until the child process exits.
The read method on the reader throws an exception if the process crashes or
  has a non-zero exit code.
The $environment argument is used as in $fork.
*/
from --environment/Map?=null arguments -> OpenPipe:
  if arguments is string:
    return from [arguments]
  pipe-ends := OpenPipe false --child-process-name=arguments[0]
  stdout := pipe-ends.fd
  pipes := fork --environment=environment true PIPE-INHERITED stdout PIPE-INHERITED arguments[0] arguments
  pipe-ends.pid = pipes[3]
  return pipe-ends

/// Variant of $(backticks arguments).
backticks --environment/Map?=null command arg1 -> string:
  return backticks --environment=environment [command, arg1]

/// Variant of $(backticks arguments).
backticks --environment/Map?=null command arg1 arg2 -> string:
  return backticks --environment=environment [command, arg1, arg2]

/// Variant of $(backticks arguments).
backticks --environment/Map?=null command arg1 arg2 arg3 -> string:
  return backticks --environment=environment [command, arg1, arg2, arg3]

/// Variant of $(backticks arguments).
backticks --environment/Map?=null command arg1 arg2 arg3 arg4 -> string:
  return backticks --environment=environment [command, arg1, arg2, arg3, arg4]

/**
Forks a program, and return the output from its stdout.
Uses PATH to find the program.
Can be passed either a command (with no arguments) as a
  string, or an array of arguments, where the 0th argument is the command.
Throws an exception if the program exits with a signal or a non-zero
  exit value.
The $environment argument is used as in $fork.
*/
backticks --environment/Map?=null arguments -> string:
  if arguments is string:
    return backticks --environment=environment [arguments]
  pipe-ends := OpenPipe false
  stdout := pipe-ends.fd
  pipes := fork --environment=environment true PIPE-INHERITED stdout PIPE-INHERITED arguments[0] arguments
  child-process := pipes[3]
  pipe-ends.in.buffer-all
  output := pipe-ends.in.read-string (pipe-ends.in.buffered-size)
  try:
    check-exit_ child-process arguments[0]
  finally:
    catch: pipe-ends.close
  return output

/**
Returns the exit value of the process which can then be decoded into
  exit code or signal number.

See $exit-code and $exit-signal.
*/
wait-for child-process:
  wait-for_ child-process
  state := monitor.ResourceState_ process-resource-group_ child-process
  exit-value := state.wait
  state.dispose
  return exit-value

/**
Forks a program, and returns the exit status.
A return value of zero indicates the program ran without errors.
Uses the /bin/sh shell to parse the command, which is a single string.
Arguments are split by the shell at unescaped whitespace.
  On Windows we just split at spaces, since the shell is not available.
  For more complicated cases where this is insufficient, use $run-program.
Throws an exception if the shell cannot be run, but otherwise returns the
  exit value of shell, which is the exit value of the program it ran.
If the program run by the shell dies with a signal then the exit value is 128 +
  the signal number.
The $environment argument is used as in $fork.
*/
system --environment/Map?=null command -> int?:
  if sdk-system.platform == sdk-system.PLATFORM-WINDOWS:
    return run-program --environment=environment ["cmd", "/s", "/c"] + (command.split " ")
  else:
    return run-program --environment=environment ["/bin/sh", "-c", command]

/// Variant of $(run-program arguments).
run-program --environment/Map?=null command arg1 -> int?:
  return run-program [command, arg1]

/// Variant of $(run-program arguments).
run-program --environment/Map?=null command arg1 arg2 -> int?:
  return run-program [command, arg1, arg2]

/// Variant of $(run-program arguments).
run-program --environment/Map?=null command arg1 arg2 arg3 -> int?:
  return run-program [command, arg1, arg2, arg3]

/// Variant of $(run-program arguments).
run-program --environment/Map?=null command arg1 arg2 arg3 arg4 -> int?:
  return run-program [command, arg1, arg2, arg3, arg4]

/**
Forks a program, and returns the exit status.
A return value of zero indicates the program ran without errors.
Can be passed either a command (with no arguments) as a
  string, or an array of arguments, where the 0th argument is the command.
Throws an exception if the command cannot be run or if the command exits
  with a signal, but otherwise returns the exit value of the program.
The $environment argument is used as in $fork.
*/
run-program --environment/Map?=null arguments -> int:
  if arguments is string:
    return run-program [arguments]
  pipes := fork --environment=environment true PIPE-INHERITED PIPE-INHERITED PIPE-INHERITED arguments[0] arguments
  child-process := pipes[3]
  exit-value := wait-for child-process
  signal := exit-signal exit-value
  if signal:
    throw
      "$arguments[0]: " +
        signal-to-string signal
  return exit-code exit-value

stdin:
  return get-standard-pipe_ 0

stdout:
  return get-standard-pipe_ 1

stderr:
  return get-standard-pipe_ 2

print-to-stdout message/string -> none:
  print-to_ stdout message

print-to-stderr message/string -> none:
  print-to_ stderr message


/**
Decodes the exit value (of $wait-for) and returns the exit code.

Returns null if the process exited due to an uncaught signal. Use $exit-signal
  in that case.
*/
exit-code exit-value/int -> int?:
  if (exit-value & PROCESS-SIGNALLED_) != 0: return null
  return (exit-value >> PROCESS-EXIT-CODE-SHIFT_) & PROCESS-EXIT-CODE-MASK_

/**
Decodes the exit value (of $wait-for) and returns the exit signal.

Returns null if the process exited normally with an exit code, and not
  because of an uncaught signal. Use $exit-code in that case.

Use $signal-to-string to convert the signal to a string.
*/
exit-signal exit-value/int -> int?:
  if (exit-value & PROCESS-SIGNALLED_) == 0: return null
  return (exit-value >> PROCESS-SIGNAL-SHIFT_) & PROCESS-SIGNAL-MASK_

// Temporary method, until printing to stdout is easier without allocating a `Writer`.
print-to_ pipe msg/string:
  writer/io.Writer := pipe.out
  writer.write msg
  writer.write "\n"

is-a-tty_ resource:
  #primitive.pipe.is-a-tty

fork_ group use-path stdin stdout stderr fd-3 fd-4 command arguments environment:
  #primitive.pipe.fork2

fd-to-pipe_ resource-group fd:
  #primitive.pipe.fd-to-pipe

process-init_:
  #primitive.subprocess.init

dont-wait-for subprocess -> none:
  #primitive.subprocess.dont-wait-for

wait-for_ subprocess -> none:
  #primitive.subprocess.wait-for

kill_ subprocess signal:
  #primitive.subprocess.kill

signal-to-string signal:
  #primitive.subprocess.strsignal
