# Copying /proc/../smaps from a target

As the files in /proc are not real files and mostly have a size of 0
(despite having content), it's not straight forward copying them from a
target device to your development machine.

Add dropbear instead of openssh on the target into the mix and it becomes
even more cumbersome.

Here's a bash snippet that should work for any target that has either a dropbear or
openssh daemon running:

```
#!/bin/bash

pids=...

myproc=/tmp/myproc

rm -rf $myproc
mkdir $myproc

function createSFTPBatch { 
  echo "cd /proc"
  echo "lcd $myproc"
  for pid in $pids; do
     echo "lmkdir $pid"
     echo "-get $pid/smaps $pid"
     echo "-get $pid/cmdline $pid"
  done
  echo "bye"
}

createSFTPBatch | sftp -q ...
```
