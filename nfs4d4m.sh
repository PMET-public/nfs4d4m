#!/usr/bin/env bash

# stop on errors
#set -e
# turn on debugging
#set -x

local_username=$(logname)

if [ ! -f "$1" ]; then
  echo "$1 is not a regular file" && exit 1
fi
mount_file="$1"

# create tmp dir for file manipulation
mkdir -p .tmp || :

# clean up and standardize mounts file format
# remove leading & trailing whitespace, extra "/"s, empty & duplicate lines, append ':' to lines with only a local path
while read line; do echo -e "$line"; done < "${mount_file}" | 
  sed '/ *#.*/d;s/\/*$//;s/\/*:/:/;/^$/d;/:/!s/$/:/' |
  sort | uniq > .tmp/mounts

# check local paths exist and update local paths to explicit paths
line_num=0
for local_path in $(sed 's/:.*//' .tmp/mounts | sort); do
  ((line_num++))
  eval "local_path=${local_path}"
  if ! $(cd ${local_path}); then
    echo "Error: ${local_path} does not exist;" && exit 1
  fi
  resolved_local_path=$( cd "${local_path}"; pwd -P )
  sed -i.bak "${line_num}s|.*:|${resolved_local_path}:|" .tmp/mounts
done

# if remote path omitted; use same path remotely
# unless path begins with osx /private, remove that
# also remove any duplicates resulting from transformations
awk -F ':' '{print $1 ":" (($2=="") ? (sub(/^\/private/, "", $1) ? $1 : $1) : $2)}' .tmp/mounts | sort | uniq > .tmp/awk
mv .tmp/awk .tmp/mounts

# check no mount is a child of another
prev_path="this-is-a-fake-path"
for local_path in $(sed 's/:.*//' .tmp/mounts | sort); do
  if [ "${local_path}" == "${prev_path}" ] || [[ "${local_path}" =~ "${prev_path}/" ]]; then
    echo -e "You can't export both\n'${prev_path}'\nand its child:\n'${local_path}'" && exit 1
  fi
  prev_path="${local_path}"
done

# verify that remote mounts for duplication
prev_path="this-is-a-fake-path"
for remote_path in $(sed 's/.*://' .tmp/mounts | sort); do
  if [ "${remote_path}" == "${prev_path}" ] || [[ "${resolved_local_path}" =~ "${prev_path}/" ]]; then
    echo "You can't remotely mount to both '${prev_path}' and '${remote_path}'" && exit 1
  fi
  prev_path="${remote_path}"
done

# remove old d4m entries from local /etc/exports
perl -i -pe 'BEGIN{undef $/;} s/# d4m.*# d4m\n?//sm' /etc/exports

# add new d4m exports
nfs_uid=$(id -u "${local_username}")
nfs_gid=$(id -g "${local_username}")
for local_path in $(sed 's/:.*//' .tmp/mounts); do
    local_path=$( cd "${local_path}"; pwd -P )
    exports="${exports}\n${local_path} -alldirs -mapall=${nfs_uid}:${nfs_gid} localhost"
done
echo -e "# d4m${exports}\n# d4m" >> /etc/exports

if ! nfsd checkexports; then
  echo "The command 'nfsd checkexports' failed. Check /etc/exports." && exit 1
fi

# check if necessary nfs conf line exists 
# https://superuser.com/questions/183588/nfs-share-from-os-x-snow-leopard-to-ubuntu-linux
nfs_conf_line="nfs.server.mount.require_resv_port = 0"
if ! grep -q "${nfs_conf_line}" /etc/nfs.conf; then
  echo "${nfs_conf_line}" >> /etc/nfs.conf
fi

# restart nfsd
killall -9 nfsd; nfsd start

# wait until nfs is up
while ! rpcinfo -u localhost nfs > /dev/null 2>&1; do
  echo -n "." && sleep 1
done

echo "Done."
