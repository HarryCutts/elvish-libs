# Directory history management
#
# Keep and move through the directory history, including a graphical
# chooser, similar to Elvish's Location mode, but showing a chronological
# directory history instead of a weighted one.
#
# Example of use:
#
#     use dir
#     dir:setup
#     edit:insert:binding[Alt-b] = $dir:&left-word-or-prev-dir
#     edit:insert:binding[Alt-f] = $dir:&right-word-or-next-dir
#     edit:insert:binding[Alt-i] = $dir:&dir-chooser
#     fn cd [@dir]{ dir:cd $@dir }

use builtin

# Hooks to run before and after the directory chooser
before-chooser = []
after-chooser = []

# Hooks to run before and after any directory change
before-cd = []
after-cd = []

# The stack and a pointer into it, which points to the current
# directory. Normally the cursor points to the end of the stack, but
# it can move with `back` and `forward`
-dirstack = [ $pwd ]
-cursor = (- (count $-dirstack) 1)

# Maximum stack size, 0 for no limit
-max-stack-size = 100

fn stack { put $@-dirstack }

fn history {
  index = 0
  each [dir]{
    if (== $index $-cursor) {
      echo (edit:styled "* "$dir green)
    } else {
      echo "  "$dir
    }
    index = (+ $index 1)
  } $-dirstack
}

fn stacksize { count $-dirstack }

# Current directory in the stack, empty string if stack is empty
fn curdir {
  if (> (stacksize) 0) {
    put $-dirstack[$-cursor]
  } else {
    put ""
  }
}

# Cut everything after $cursor from the stack
fn -trimstack {
  -dirstack = $-dirstack[0:(+ $-cursor 1)]
}

# Add $pwd into the stack at $-cursor, only if it's different than the
# current directory (i.e. you can call push multiple times in the same
# directory, for example as part of a prompt hook, and it will only be
# added once). Pushing a directory invalidates (if any) any
# directories after it in the history.
fn push {
  if (or (== (stacksize) 0) (!=s $pwd (curdir))) {
    -dirstack = [ (explode $-dirstack[0:(+ $-cursor 1)]) $pwd ]
    if (> (stacksize) $-max-stack-size) {
      -dirstack = $-dirstack[(- $-max-stack-size):]
    }
    -cursor = (- (stacksize) 1)
  }
}

# cd wrapper which supports "-" to indicate the previous directory
fn -cd [@dir]{
  for hook $before-cd { $hook }
  if (and (== (count $dir) 1) (eq $dir[0] "-")) {
    builtin:cd $-dirstack[(- $-cursor 1)]
  } else {
    builtin:cd $@dir
  }
  push
  for hook $after-cd { $hook }
}

# Wrapper entrypoint for -cd
fn cd [@dir]{ -cd $@dir }

# cd to the base directory of the argument
fn cdb [p]{ cd (dirname $p) }

# Move back and forward through the stack.
fn back {
  if (> $-cursor 0) {
    -cursor = (- $-cursor 1)
    -cd $-dirstack[$-cursor]
  } else {
    echo "Beginning of directory history!"
  }
}

fn forward {
  if (< $-cursor (- (stacksize) 1)) {
    -cursor = (+ $-cursor 1)
    -cd $-dirstack[$-cursor]
  } else {
    echo "End of directory history!"
  }
}

# Pop the previous directory on the stack, removes the current
# one. Pop doesn't do a push afterwards, so successive pops walk back
# the stack until it's empty.
fn pop {
  if (> $-cursor 0) {
    back
    -trimstack
  } else {
    echo "No previous directory to pop!"
  }
}

# Utility functions to move the cursor by a word or move through
# the directory history, depending on the contents of the command
fn left-word-or-prev-dir {
  if (> (count $edit:current-command) 0) {
    edit:move-dot-left-word
  } else {
    back
  }
}

fn right-word-or-next-dir {
  if (> (count $edit:current-command) 0) {
    edit:move-dot-right-word
  } else {
    forward
  }
}

# Interactive dir history chooser
fn history-chooser {
  for hook $before-chooser { $hook }
  index = 0
  candidates = [(each [arg]{
        put [
          &content=$arg
          &display=$index" "$arg
          &filter-text=$index" "$arg
        ]
        index = (+ $index 1)
  } $-dirstack)]
  edit:-narrow-read {
    put $@candidates
  } [arg]{
    -cd $arg[content]
    for hook $after-chooser { $hook }
  } &modeline="Dir history " &ignore-case=$true &keep-bottom=$true
}

fn setup {
  # Set up a hook to call "dir:cd ." on every prompt, to push the new
  # directory (if any) and to run any cd hooks.
  edit:before-readline = [ $@edit:before-readline { -cd . } ]
  # If `narrow` is loaded, call "dir:cd ." after every change, to push
  # the new directory onto the stack and run any cd hooks
  _ = ?(narrow:after-location = [ $@narrow:after-location { -cd . } ])
}
