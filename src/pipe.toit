// Copyright (C) 2018 Toitware ApS.
// Use of this source code is governed by an MIT-style license that can be
// found in the package's LICENSE file.

import .file as file
import io
import monitor
import reader as old-reader
import system as sdk-system

import .stream

export Stream

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

get-standard-pipe_ fd/int -> Stream:
  if not standard-pipes_[fd]:
    if file.is-open-file_ fd:
      standard-pipes_[fd] = file.OpenFile_.internal_ fd
    else:
      standard-pipes_[fd] = OpenPipe_.from-std_ (fd-to-pipe_ pipe-resource-group_ fd)
  return standard-pipes_[fd]

/**
A program may be executed with an open file descriptor.  This is similar
  to the technique used by the shell to launch programs with their stdin,
  stdout and stderr attached to pipes or files.  Given the number of
  the file descriptor this function will return a $old-reader.Reader or writer
  object.  You are expected to know which direction the file descriptor has.
*/
get-numbered-pipe fd/int -> Stream:
  if fd < 0: throw "OUT_OF_RANGE"
  if fd <= 2: throw "Use stdin, stdout, stderr"
  if file.is-open-file_ fd:
    return file.OpenFile_.internal_ fd
  else:
    return OpenPipe_.from-std_ (fd-to-pipe_ pipe-resource-group_ fd)

class OpenPipeReader_ extends io.CloseableReader:
  pipe_/OpenPipe_

  constructor .pipe_:

  read_ -> ByteArray?:
    return pipe_.read_

  close_ -> none:
    pipe_.close

/**
Deprecated. This class was never supposed to be public.
*/
class OpenPipeWriter extends OpenPipeWriter_:
  constructor pipe:
    super pipe

class OpenPipeWriter_ extends io.CloseableWriter:
  pipe_/OpenPipe_

  constructor .pipe_:

  try-write_ data/io.Data from/int to/int -> int:
    return pipe_.try-write_ data from to

  close_ -> none:
    pipe_.close

/**
Deprecated. Use $(Stream.constructor --parent-to-child) or
  $(Stream.constructor --child-to-parent) to construct pipes.
*/
class OpenPipe extends OpenPipe_:
  constructor input/bool --child-process-name="child process":
    super input --child-process-name=child-process-name

class OpenPipe_ implements Stream:
  resource_ := ?
  state_ := ?
  pid := null
  child-process-name_ /string?
  input_ /int := UNKNOWN-DIRECTION_

  fd_/any  // Other end of descriptor, for child process.
  in_ /OpenPipeReader_? := null
  out_ /OpenPipeWriter_? := null

  constructor input/bool --child-process-name="child process":
    group := pipe-resource-group_
    pipe-pair := create-pipe_ group input
    input_ = input ? PARENT-TO-CHILD_ : CHILD-TO-PARENT_
    child-process-name_ = child-process-name
    resource_ = pipe-pair[0]
    fd_ = pipe-pair[1]
    state_ = monitor.ResourceState_ pipe-resource-group_ resource_
    if input:
      in_ = null
      out_ = OpenPipeWriter_ this
    else:
      in_ = OpenPipeReader_ this
      out_ = null

  constructor.from-std_ .resource_:
    group := pipe-resource-group_
    child-process-name_ = null
    state_ = monitor.ResourceState_ pipe-resource-group_ resource_
    fd_ = -1
    in_ = OpenPipeReader_ this
    out_ = OpenPipeWriter_ this

  /** Deprecated. */
  fd -> any:
    return fd_

  in -> io.CloseableReader:
    if not in_:
      throw "use of output pipe as input"
    return in_

  out -> io.CloseableWriter:
    if not out_:
      throw "use of input pipe as output"
    return out_

  /**
  Deprecated. Use 'read' on $in instead.
  */
  read -> ByteArray?:
    return in.read

  read_ -> ByteArray?:
    while true:
      state_.wait-for-state READ-EVENT_ | CLOSE-EVENT_
      result := read-from-pipe_ resource_
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
    if from == to: return 0
    state_.wait-for-state WRITE-EVENT_ | ERROR-EVENT_
    bytes-written := write-to-pipe_ resource_ data from to
    if bytes-written == 0: state_.clear-state WRITE-EVENT_
    return bytes-written

  close:
    close-resource_ resource_
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
    exit-value := Process.wait_ pid
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

write-to-pipe_ pipe data/io.Data from to:
  #primitive.pipe.write: | error |
    written := 0
    io.primitive-redo-chunked-io-data_ error data from to: | chunk/ByteArray |
      chunk-written := write-to-pipe_ pipe chunk 0 chunk.size
      written += chunk-written
      if chunk-written < chunk.size: return written
    return written

read-from-pipe_ pipe:
  #primitive.pipe.read

close-resource_ pipe:
  return close-resource_ pipe pipe-resource-group_

close-resource_ pipe resource-group:
  #primitive.pipe.close

/// Use the stdin/stdout/stderr that the parent Toit process has.
PIPE-INHERITED ::= -1
/// Create new pipe and return it.
PIPE-CREATED ::= -2

/**
Forks a process.

Deprecated. Use $(fork command arguments) instead.
*/
fork use-path stdin stdout stderr command arguments -> List
    --environment/Map?=null
    --file-descriptor-3/Stream?=null
    --file-descriptor-4/Stream?=null:
  return fork_ use-path stdin stdout stderr command arguments
    --environment=environment
    --file-descriptor-3=file-descriptor-3
    --file-descriptor-4=file-descriptor-4

/** The result of forking a process with $fork. */
class Process:
  fork-data_/List

  constructor .fork-data_:

  /** The pid of the child process. */
  pid -> any: return fork-data_[3]

  /**
  The stdin stream.

  Returns null, if the stream wasn't created during forking.
  */
  stdin -> Stream?: return fork-data_[0]

  /**
  The stdout stream.

  Returns null, if the stream wasn't created during forking.
  */
  stdout -> Stream?: return fork-data_[1]

  /**
  The stderr stream.

  Returns null, if the stream wasn't created during forking.
  */
  stderr -> Stream?: return fork-data_[2]

  /**
  Wait for the process to finish and return the exit-value.

  Use $exit-signal and $exit-code to decode the exit value.
  */
  wait -> int:
    return wait_ pid

  static wait_ child-process -> int:
    wait-for_ child-process
    state := monitor.ResourceState_ process-resource-group_ child-process
    exit-value := state.wait
    state.dispose
    return exit-value

  /**
  Tells the system that we don't want to wait for the child process to finish.
  */
  wait-ignore -> none:
    dont-wait-for_ pid

/**
Forks a process.

Attaches the given $stdin, $stdout, $stderr streams to the corresponding
  streams of the child process. If a stream is null, then it is inherited.
  Use $(Stream.constructor --parent-to-child) or $(Stream.constructor --child-to-parent)
  to create a fresh pipe.
Alternatively, a pipe can be created using the $create-stdin,
  $create-stdout, and $create-stderr flags. In this case use $Process.stdin,
  $Process.stdout, and $Process.stderr to access the streams.
The $stdin and $create-stdin (respectively $stdout and $create-stdout,
  $stderr and $create-stderr) arguments are mutually exclusive.

To avoid zombies you must either cal $Process.wait-ignore or $Process.wait.

The $file-descriptor-3 and $file-descriptor-4 can be used to pass streams as
  open file descriptors 3 and/or 4 to the child process.

The $environment variable, if given, must be a map where the keys are strings and
  the values strings or null, where null indicates that the variable should be
  unset in the child process.

If you override the PATH environment variable, but set the $use-path
  flag, the new value of PATH will be used to find the executable.
*/
fork command/string arguments/List -> Process
    --use-path/bool=true
    --environment/Map?=null
    --stdin/Stream?=null
    --stdout/Stream?=null
    --stderr/Stream?=null
    --create-stdin/bool=false
    --create-stdout/bool=false
    --create-stderr/bool=false
    --file-descriptor-3/Stream?=null
    --file-descriptor-4/Stream?=null:
  if create-stdin and stdin: throw "ARGUMENT_ERROR"
  if create-stdout and stdout: throw "ARGUMENT_ERROR"
  if create-stderr and stderr: throw "ARGUMENT_ERROR"
  stdin-arg := ?
  if stdin: stdin-arg = stdin
  else if create-stdin: stdin-arg = PIPE-CREATED
  else: stdin-arg = PIPE-INHERITED
  stdout-arg := ?
  if stdout: stdout-arg = stdout
  else if create-stdout: stdout-arg = PIPE-CREATED
  else: stdout-arg = PIPE-INHERITED
  stderr-arg := ?
  if stderr: stderr-arg = stderr
  else if create-stderr: stderr-arg = PIPE-CREATED
  else: stderr-arg = PIPE-INHERITED
  fork-data := fork_
    use-path
    stdin-arg
    stdout-arg
    stderr-arg
    command
    arguments
    --environment=environment
    --file-descriptor-3=file-descriptor-3
    --file-descriptor-4=file-descriptor-4

  return Process fork-data

fork_ use-path stdin stdout stderr command arguments -> List
    --environment/Map?=null
    --file-descriptor-3/Stream?=null
    --file-descriptor-4/Stream?=null:
  if (arguments.any: it is not string):
    throw "INVALID_ARGUMENT"
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
      pipe := OpenPipe_ true
      result[0] = pipe
      stdin = pipe.fd_
    if stdout == PIPE-CREATED:
      pipe := OpenPipe_ false
      result[1] = pipe
      stdout = pipe.fd_
    if stderr == PIPE-CREATED:
      pipe := OpenPipe_ false
      result[2] = pipe
      stderr = pipe.fd_
    fd-3 := file-descriptor-3 ? file-descriptor-3.fd_ : -1
    fd-4 := file-descriptor-4 ? file-descriptor-4.fd_ : -1
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
  accumulator := io.Buffer.with-capacity (path.size + 4 + (path.size >> 2))
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
to --environment/Map?=null command/string arg1/string -> Stream:
  return to --environment=environment [command, arg1]

/// Variant of $(to arguments).
to --environment/Map?=null command/string arg1/string arg2/string -> Stream:
  return to --environment=environment [command, arg1, arg2]

/// Variant of $(to arguments).
to --environment/Map?=null command/string arg1/string arg2/string arg3/string -> Stream:
  return to --environment=environment [command, arg1, arg2, arg3]

/// Variant of $(to arguments).
to --environment/Map?=null command/string arg1/string arg2/string arg3/string arg4/string -> Stream:
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
to --environment/Map?=null arguments -> Stream:
  if arguments is string:
    arguments = [arguments]
  pipe-ends := OpenPipe_ true --child-process-name=arguments[0]
  stdin := pipe-ends.fd_
  pipes := fork_ --environment=environment true stdin PIPE-INHERITED PIPE-INHERITED arguments[0] arguments
  pipe-ends.pid = pipes[3]
  return pipe-ends

/// Variant of $(from arguments).
from --environment/Map?=null command/string arg1/string -> Stream:
  return from --environment=environment [command, arg1]

/// Variant of $(from arguments).
from --environment/Map?=null command/string arg1/string arg2/string -> Stream:
  return from --environment=environment [command, arg1, arg2]

/// Variant of $(from arguments).
from --environment/Map?=null command/string arg1/string arg2/string arg3/string -> Stream:
  return from --environment=environment [command, arg1, arg2, arg3]

/// Variant of $(from arguments).
from --environment/Map?=null command/string arg1/string arg2/string arg3/string arg4/string -> Stream:
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
from --environment/Map?=null arguments -> Stream:
  if arguments is string:
    arguments = [arguments]
  pipe-ends := OpenPipe_ false --child-process-name=arguments[0]
  stdout := pipe-ends.fd_
  pipes := fork_ --environment=environment true PIPE-INHERITED stdout PIPE-INHERITED arguments[0] arguments
  pipe-ends.pid = pipes[3]
  return pipe-ends

/// Variant of $(backticks arguments).
backticks --environment/Map?=null command/string arg1/string -> string:
  return backticks --environment=environment [command, arg1]

/// Variant of $(backticks arguments).
backticks --environment/Map?=null command/string arg1/string arg2/string -> string:
  return backticks --environment=environment [command, arg1, arg2]

/// Variant of $(backticks arguments).
backticks --environment/Map?=null command/string arg1/string arg2/string arg3/string -> string:
  return backticks --environment=environment [command, arg1, arg2, arg3]

/// Variant of $(backticks arguments).
backticks --environment/Map?=null command/string arg1/string arg2/string arg3/string arg4/string -> string:
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
    arguments = [arguments]
  pipe-ends := OpenPipe_ false
  stdout := pipe-ends.fd_
  pipes := fork_ --environment=environment true PIPE-INHERITED stdout PIPE-INHERITED arguments[0] arguments
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

Deprecated. Use $Process.wait instead.
*/
wait-for child-process:
  return Process.wait_ child-process

/**
Deprecated. Use $Process.wait-ignore instead.
*/
dont-wait-for subprocess -> none:
  dont-wait-for_ subprocess

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
run-program --environment/Map?=null command/string arg1/string -> int?:
  return run-program [command, arg1]

/// Variant of $(run-program arguments).
run-program --environment/Map?=null command/string arg1/string arg2/string -> int?:
  return run-program [command, arg1, arg2]

/// Variant of $(run-program arguments).
run-program --environment/Map?=null command/string arg1/string arg2/string arg3/string -> int?:
  return run-program [command, arg1, arg2, arg3]

/// Variant of $(run-program arguments).
run-program --environment/Map?=null command/string arg1/string arg2/string arg3/string arg4/string -> int?:
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
    arguments = [arguments]
  pipes := fork_ --environment=environment true PIPE-INHERITED PIPE-INHERITED PIPE-INHERITED arguments[0] arguments
  child-process := pipes[3]
  exit-value := Process.wait_ child-process
  signal := exit-signal exit-value
  if signal:
    throw
      "$arguments[0]: " +
        signal-to-string signal
  return exit-code exit-value

/** The stdin of the current process. */
stdin -> Stream:
  return get-standard-pipe_ 0

/** The stdout of the current process. */
stdout -> Stream:
  return get-standard-pipe_ 1

/** The stderr of the current process. */
stderr -> Stream:
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

dont-wait-for_ subprocess -> none:
  #primitive.subprocess.dont-wait-for

wait-for_ subprocess -> none:
  #primitive.subprocess.wait-for

kill_ subprocess signal:
  #primitive.subprocess.kill

signal-to-string signal:
  #primitive.subprocess.strsignal
