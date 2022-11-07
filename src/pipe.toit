// Copyright (C) 2018 Toitware ApS.
// Use of this source code is governed by an MIT-style license that can be
// found in the package's LICENSE file.

import .file as file
import reader
import monitor
import writer show Writer

process_resource_group_ ::= process_init_
pipe_resource_group_ ::= pipe_init_
standard_pipes_ ::= [ null, null, null ]

// Keep in sync with similar list in event_sources/subprocess.cc.
PROCESS_EXITED_ ::= 1
PROCESS_SIGNALLED_ ::= 2
PROCESS_EXIT_CODE_SHIFT_ ::= 2
PROCESS_EXIT_CODE_MASK_ ::= 0xff
PROCESS_SIGNAL_SHIFT_ ::= 10
PROCESS_SIGNAL_MASK_ ::= 0xff

READ_EVENT_ ::= 1 << 0
WRITE_EVENT_ ::= 1 << 1
CLOSE_EVENT_ ::= 1 << 2
ERROR_EVENT_ ::= 1 << 3

UNKNOWN_DIRECTION_ ::= 0
PARENT_TO_CHILD_ ::= 1
CHILD_TO_PARENT_ ::= 2


get_standard_pipe_ fd/int:
  if not standard_pipes_[fd]:
    if file.is_open_file_ fd:
      standard_pipes_[fd] = file.Stream.internal_ fd  // TODO: This is a private constructor.
    else:
      standard_pipes_[fd] = OpenPipe.from_std_ (fd_to_pipe_ pipe_resource_group_ fd)
  return standard_pipes_[fd]

/**
A program may be executed with an open file descriptor.  This is similar
  to the technique used by the shell to launch programs with their stdin,
  stdout and stderr attached to pipes or files.  Given the number of
  the file descriptor this function will return a $reader.Reader or writer
  object.  You are expected to know which direction the file descriptor has.
*/
get_numbered_pipe fd/int:
  if fd < 0: throw "OUT_OF_RANGE"
  if fd <= 2: throw "Use stdin, stdout, stderr"
  if file.is_open_file_ fd:
    return file.Stream.internal_ fd  // TODO: This is a private constructor.
  else:
    return OpenPipe.from_std_ (fd_to_pipe_ pipe_resource_group_ fd)

class OpenPipe implements reader.Reader:
  resource_ := ?
  state_ := ?
  pid := null
  child_process_name_ /string?
  input_ /int := UNKNOWN_DIRECTION_

  fd := -1  // Other end of descriptor, for child process.

  constructor input/bool --child_process_name="child process":
    group := pipe_resource_group_
    pipe_pair := create_pipe_ group input
    input_ = input ? PARENT_TO_CHILD_ : CHILD_TO_PARENT_
    child_process_name_ = child_process_name
    resource_ = pipe_pair[0]
    fd = pipe_pair[1]
    state_ = monitor.ResourceState_ pipe_resource_group_ resource_

  constructor.from_std_ .resource_:
    group := pipe_resource_group_
    child_process_name_ = null
    state_ = monitor.ResourceState_ pipe_resource_group_ resource_

  read -> ByteArray?:
    if input_ == PARENT_TO_CHILD_:
      throw "read from an output pipe"
    while true:
      state_.wait_for_state READ_EVENT_ | CLOSE_EVENT_
      result := read_ resource_
      if result != -1:
        if result == null:
          try:
            check_exit_ pid child_process_name_
          finally:
            pid = null
        return result
      state_.clear_state READ_EVENT_

  write x from = 0 to = x.size:
    if input_ == CHILD_TO_PARENT_:
      throw "write to an input pipe"
    state_.wait_for_state WRITE_EVENT_ | ERROR_EVENT_
    bytes_written := write_primitive_ resource_ x from to
    if bytes_written == 0: state_.clear_state WRITE_EVENT_
    return bytes_written

  close:
    close_ resource_
    if state_:
      state_.dispose
      state_ = null
    if input_ == PARENT_TO_CHILD_:
      check_exit_ pid child_process_name_

  is_a_terminal -> bool:
    return is_a_tty_ resource_

check_exit_ pid child_process_name/string? -> none:
  if child_process_name == null:
    child_process_name = "child process"
  if pid:
    exit_value := wait_for pid
    if (exit_value & PROCESS_SIGNALLED_) != 0:
      // Process crashed.
      throw
        "$child_process_name: " +
          signal_to_string (exit_signal exit_value)
    code := exit_code exit_value
    if code != 0:
      throw "$child_process_name: exited with status $code"

pipe_fd_ resource:
  #primitive.pipe.fd

pipe_init_:
  #primitive.pipe.init

create_pipe_ resource_group input/bool:
  #primitive.pipe.create_pipe

write_primitive_ pipe x from to:
  #primitive.pipe.write

read_ pipe:
  #primitive.pipe.read

close_ pipe:
  return close_ pipe pipe_resource_group_

close_ pipe resource_group:
  #primitive.pipe.close

/// Use the stdin/stdout/stderr that the parent Toit process has.
PIPE_INHERITED ::= -1
/// Create new pipe and return it.
PIPE_CREATED ::= -2

create_pipe_helper_ input_flag index result:
  pipe_ends := OpenPipe input_flag
  result[index] = pipe_ends
  return pipe_ends.fd

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
*/
fork use_path stdin stdout stderr --file_descriptor_3/OpenPipe?=null --file_descriptor_4/OpenPipe?=null command arguments -> List:
  result := List 4
  exception := catch:
    if stdin == PIPE_CREATED:
      stdin = create_pipe_helper_ true 0 result
    if stdout == PIPE_CREATED:
      stdout = create_pipe_helper_ false 1 result
    if stderr == PIPE_CREATED:
      stderr = create_pipe_helper_ false 2 result
    fd_3 := file_descriptor_3 ? file_descriptor_3.fd : -1
    fd_4 := file_descriptor_4 ? file_descriptor_4.fd : -1
    result[3] = fork_ process_resource_group_ use_path stdin stdout stderr fd_3 fd_4 command (Array_.ensure arguments)
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
    if (command.index_of " ") != -1:
      throw "Error trying to run executable with a space in the filename: '$command': $exception"
    else:
      clarification := ""
      if command.size > 0 and command[0] != '/':
        clarification = use_path ? " using \$PATH" : " not using path"
      throw "Error trying to run '$command'$clarification: $exception"
  return result

to command arg1:
  return to [command, arg1]

to command arg1 arg2:
  return to [command, arg1, arg2]

to command arg1 arg2 arg3:
  return to [command, arg1, arg2, arg3]

to command arg1 arg2 arg3 arg4:
  return to [command, arg1, arg2, arg3, arg4]

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
*/
to arguments:
  if arguments is string:
    return to [arguments]
  pipe_ends := OpenPipe true --child_process_name=arguments[0]
  stdin := pipe_ends.fd
  pipes := fork true stdin PIPE_INHERITED PIPE_INHERITED arguments[0] arguments
  pipe_ends.pid = pipes[3]
  return pipe_ends

from command arg1:
  return from [command, arg1]

from command arg1 arg2:
  return from [command, arg1, arg2]

from command arg1 arg2 arg3:
  return from [command, arg1, arg2, arg3]

from command arg1 arg2 arg3 arg4:
  return from [command, arg1, arg2, arg3, arg4]

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
*/
from arguments:
  if arguments is string:
    return from [arguments]
  pipe_ends := OpenPipe false --child_process_name=arguments[0]
  stdout := pipe_ends.fd
  pipes := fork true PIPE_INHERITED stdout PIPE_INHERITED arguments[0] arguments
  pipe_ends.pid = pipes[3]
  return pipe_ends

backticks command arg1 -> string:
  return backticks [command, arg1]

backticks command arg1 arg2 -> string:
  return backticks [command, arg1, arg2]

backticks command arg1 arg2 arg3 -> string:
  return backticks [command, arg1, arg2, arg3]

backticks command arg1 arg2 arg3 arg4 -> string:
  return backticks [command, arg1, arg2, arg3, arg4]

/**
Forks a program, and return the output from its stdout.
Uses PATH to find the program.
Can be passed either a command (with no arguments) as a
  string, or an array of arguments, where the 0th argument is the command.
Throws an exception if the program exits with a signal or a non-zero
  exit value.
*/
backticks arguments -> string:
  if arguments is string:
    return backticks [arguments]
  pipe_ends := OpenPipe false
  stdout := pipe_ends.fd
  pipes := fork true PIPE_INHERITED stdout PIPE_INHERITED arguments[0] arguments
  child_process := pipes[3]
  reader := reader.BufferedReader pipe_ends
  reader.buffer_all
  output := reader.read_string (reader.buffered)
  try:
    check_exit_ child_process arguments[0]
  finally:
    catch: pipe_ends.close
  return output

/**
Returns the exit value of the process which can then be decoded into
  exit code or signal number.

See $exit_code and $exit_signal.
*/
wait_for child_process:
  wait_for_ child_process
  state := monitor.ResourceState_ process_resource_group_ child_process
  exit_value := state.wait
  state.dispose
  return exit_value

/**
Forks a program, and returns the exit status.
A return value of zero indicates the program ran without errors.
Uses the /bin/sh shell to parse the command, which is a single string.
Arguments are split by the shell at unescaped whitespace.
Throws an exception if the shell cannot be run, but otherwise returns the
  exit value of shell, which is the exit value of the program it ran.
If the program run by the shell dies with a signal then the exit value is 128 +
  the signal number.
*/
system command -> int?:
  if platform == PLATFORM_WINDOWS:
    return run_program ["cmd", "/s", "/c",  command]
  else:
    return run_program ["/bin/sh", "-c", command]

run_program command arg1 -> int?:
  return run_program [command, arg1]

run_program command arg1 arg2 -> int?:
  return run_program [command, arg1, arg2]

run_program command arg1 arg2 arg3 -> int?:
  return run_program [command, arg1, arg2, arg3]

run_program command arg1 arg2 arg3 arg4 -> int?:
  return run_program [command, arg1, arg2, arg3, arg4]

/**
Forks a program, and returns the exit status.
A return value of zero indicates the program ran without errors.
Can be passed either a command (with no arguments) as a
  string, or an array of arguments, where the 0th argument is the command.
Throws an exception if the command cannot be run or if the command exits
  with a signal, but otherwise returns the exit value of the program.
*/
run_program arguments -> int:
  if arguments is string:
    return run_program [arguments]
  pipes := fork true PIPE_INHERITED PIPE_INHERITED PIPE_INHERITED arguments[0] arguments
  child_process := pipes[3]
  exit_value := wait_for child_process
  signal := exit_signal exit_value
  if signal:
    throw
      "$arguments[0]: " +
        signal_to_string signal
  return exit_code exit_value

stdin:
  return get_standard_pipe_ 0

stdout:
  return get_standard_pipe_ 1

stderr:
  return get_standard_pipe_ 2

print_to_stdout message/string -> none:
  print_to_ stdout message

print_to_stderr message/string -> none:
  print_to_ stderr message


/**
Decodes the exit value (of $wait_for) and returns the exit code.

Returns null if the process exited due to an uncaught signal. Use $exit_signal
  in that case.
*/
exit_code exit_value/int -> int?:
  if (exit_value & PROCESS_SIGNALLED_) != 0: return null
  return (exit_value >> PROCESS_EXIT_CODE_SHIFT_) & PROCESS_EXIT_CODE_MASK_

/**
Decodes the exit value (of $wait_for) and returns the exit signal.

Returns null if the process exited normally with an exit code, and not
  because of an uncaught signal. Use $exit_code in that case.

Use $signal_to_string to convert the signal to a string.
*/
exit_signal exit_value/int -> int?:
  if (exit_value & PROCESS_SIGNALLED_) == 0: return null
  return (exit_value >> PROCESS_SIGNAL_SHIFT_) & PROCESS_SIGNAL_MASK_

// Temporary method, until printing to stdout is easier without allocating a `Writer`.
print_to_ pipe msg/string:
  writer := Writer pipe
  writer.write msg
  writer.write "\n"

is_a_tty_ resource:
  #primitive.pipe.is_a_tty

fork_ group use_path stdin stdout stderr fd_3 fd_4 command arguments:
  #primitive.pipe.fork

fd_to_pipe_ resource_group fd:
  #primitive.pipe.fd_to_pipe

process_init_:
  #primitive.subprocess.init

dont_wait_for subprocess -> none:
  #primitive.subprocess.dont_wait_for

wait_for_ subprocess -> none:
  #primitive.subprocess.wait_for

kill_ subprocess signal:
  #primitive.subprocess.kill

signal_to_string signal:
  #primitive.subprocess.strsignal
