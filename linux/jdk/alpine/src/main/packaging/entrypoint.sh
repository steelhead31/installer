#!/usr/bin/env bash
set -euox pipefail

# Copy build scripts into a directory within the container. Avoids polluting the mounted
# directory and permission errors.
mkdir /home/builder/workspace
cp -R /home/builder/build/generated/packaging /home/builder/workspace

# Set permssions
sudo chown -R builder /home/builder/out
sudo chown -R builder /home/builder 

# Debugging
echo "Debug"
ls -ltr /var/cache
ls -ltr /home/builder/.abuild
cat /home/builder/.abuild/abuild.conf
cat /etc/group
echo ""
echo "ID"
id

# Build package and set distributions it supports
cd /home/builder/workspace/packaging
abuild -r -v



arch=$(abuild -A)

# Copy resulting files into mounted directory where artifacts should be placed.
mv /home/builder/packages/workspace/$arch/*.{apk,tar.gz} /home/builder/out
