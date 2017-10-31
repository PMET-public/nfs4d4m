#!/usr/bin/env bash

# stop on errors
#set -e
# turn on debugging
#set -x


if [ ! -f "$1" ]; then
   echo "$1 is not a regular file" && exit 1
fi
mount_file="$1"

# create tmp dir for file manipulation
mkdir -p .tmp || :

# clean up and standardize mounts file format
# remove leading and trailing whitespace, extra slashes, empty and duplicate lines
while read line; do echo -e "$line"; done < "${mount_file}" | 
  sed '/#.*/d;s/\/*$//;s/\/*:/:/;/^$/d' |
  awk -F ':' '{print $1 ":" (($2=="") ? $1 : $2)}' |
  sort | uniq > .tmp/mounts

# check local dirs and update .tmp/mounts to explicit paths
prev_dir="INITIAL_VALUE_OF_FAKE_DIR"
line_num=0
for local_dir in $(sed 's/:.*//' .tmp/mounts | sort); do
  ((line_num++))
  if ! $(cd "${local_dir}"); then
    echo "Error: '${local_dir}' does not exist;" && exit 1
  fi
  resolved_local_dir=$( cd "${local_dir}"; pwd -P )
  if [ "${resolved_local_dir}" == "${prev_dir}" ] || [[ "${resolved_local_dir}" =~ "${prev_dir}/" ]]; then
    echo "You can't export both '${prev_dir}' and '${resolved_local_dir}'" && exit 1
  fi
  prev_dir="${resolved_local_dir}"
  sed -i.bak "${line_num}s|.*:|${resolved_local_dir}:|" .tmp/mounts
done

# check remote mounts for duplication
prev_dir="INITIAL_VALUE_OF_FAKE_DIR"
for remote_dir in $(sed 's/.*://' .tmp/mounts | sort); do
  if [ "${remote_dir}" == "${prev_dir}" ] || [[ "${resolved_local_dir}" =~ "${prev_dir}/" ]]; then
    echo "You can't remotely mount to both '${prev_dir}' and '${remote_dir}'" && exit 1
  fi
  prev_dir="${remote_dir}"
done

# remove old d4m entries from local /etc/exports
perl -i -pe 'BEGIN{undef $/;} s/# d4m.*# d4m\n?//sm' /etc/exports

# add new d4m exports
logname=$(logname)
nfs_uid=$(id -u "${logname}")
nfs_gid=$(id -g "${logname}")
for local_dir in $(sed 's/:.*//' .tmp/mounts); do
    local_dir=$( cd "${local_dir}"; pwd -P )
    exports="${exports}\n${local_dir} -alldirs -mapall=${nfs_uid}:${nfs_gid} localhost"
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

# create a privileged container to execute cmds directly on the d4m vm
if ! docker ps -a --format "{{.Names}}" | grep -q d4m-helper; then
  if ! docker run --name d4m-helper -dt --privileged --pid=host debian:stable-slim bash; then
    exit 1
  fi
fi

# install nfs utils on d4m vm
docker exec d4m-helper nsenter -t 1 -m sh -c "apk update; apk add nfs-utils"

# get d4m vm's current fstab
docker exec d4m-helper nsenter -t 1 -m sh -c "cat /etc/fstab" > .tmp/d4m_fstab

# remove any old d4m entries
perl -i -pe 'BEGIN{undef $/;} s/# d4m.*# d4m\n?//sm' .tmp/d4m_fstab

# add new d4m entries
d4m_vm_default_gateway=$(docker exec d4m-helper nsenter -t 1 -m -n sh -c "ip route|awk '/default/{print \$3}'")
fstab=$(sed "s/:/ /;s/^/${d4m_vm_default_gateway}:/;s/\$/ nfs nolock,local_lock=all 0 0/" .tmp/mounts)
fstab="$(cat .tmp/d4m_fstab)\n# d4m\n${fstab}\n# d4m"

# replace d4m vm's current fstab
docker exec d4m-helper nsenter -t 1 -m sh -c "echo -e '${fstab}' > /etc/fstab"

# ensure remote dirs exist
for remote_dir in $(awk -F ':' '{print $2}' .tmp/mounts); do
  docker exec d4m-helper nsenter -t 1 -m sh -c "umount -f '${remote_dir}' 2>/dev/null; mkdir -p '${remote_dir}'"
done

# mount the nfs volumes on d4m vm
docker exec d4m-helper nsenter -t 1 -m mount -a

echo "Done."
