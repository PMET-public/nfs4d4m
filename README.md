
# Quickstart
1. Remove all mounts from Docker for Mac > Preferences > File Sharing
2. Create a mounts file (see mounts.example for file format)
3. Run `sudo ./nfs4d4m.sh mounts`

# Overview

**Docker for Mac** (d4m) includes the currently very slow osxfs. By using nfs, we can share directories on the mac into our containers much faster.

To do this, we specify which local folders that we want to mount into the d4m vm and optionally provide a path to its mount point. If no mount point is provided, the local path will be recreated remotely on the d4m vm.

If you mount to new paths, you will have to update those paths in your docker cmds and docker-compose.yml files.

# Tips
Files modified locally on the mac

* /etc/exports
* /etc/nfs.conf

Files modified remotely on the d4m vm

* /etc/fstab

# How does it work?
Check out the script. It's not too long, and there are some useful comments. 

There's some shell magic, but it's relatively short and you should be able to undertand it at a high level.


# Want to explore/debug the d4m vm?
`docker run -it --privileged --pid=host debian:stable-slim nsenter -t 1 -m -u -n -i sh`

# Bugs/Enhancments?
Please submit a pull request