
# Quickstart
1. Remove all mounts from Docker for Mac > Preferences > File Sharing
2. Create a mounts file. See mounts.example for file format but a simple example is just '..' which would share the parent path to the remote vm using the same path.
3. Run `sudo ./nfs4d4m.sh mounts`

If you make changes to your mounts file, just rerun the script and specify your new mounts file.

# Overview

**Docker for Mac** (d4m) includes osxfs (which is painfully slow for large projects). By using nfs, we can share directories on the Mac into our containers much faster.

To do this, we specify which local folders that we want to mount into the d4m virtual machine (vm) and optionally provide a path to its mount point. If no mount point is provided, the resolved local path will be recreated remotely on the d4m vm. (Local path are resolved to account for relative dirs, symlinks, etc.)

If you specify new paths to mount to on the d4m vm, you will have to update those paths in your docker cmds and docker-compose.yml files.

# Files modified locally on the mac

* /etc/exports
* /etc/nfs.conf

# Files modified remotely on the d4m vm

* /etc/fstab

# How does it work?
Check out the script. It's not too long, and there are some useful comments. 

There's some shell magic, but it's relatively short. You should be able to follow the script at a high level.


# Want to explore/debug the d4m vm?
`docker run -it --privileged --pid=host debian:stable-slim nsenter -t 1 -m -u -n -i sh`

# Bugs/Enhancments?
Please submit a pull request
