#!/bin/sh
set -eu

# The immutable bootstrap image supplies the initial compiler and signed APT keys.
# Every added package is locked by version and checked before installation.
lock_path=/toolchain/toolchain_packages.lock
apt-get update -qq
list_of_pins=$(awk '{print $1 "=" $2}' "$lock_path")
apt-get install --download-only --no-install-recommends --yes $list_of_pins
for archive in /var/cache/apt/archives/*.deb; do
  package=$(dpkg-deb -f "$archive" Package)
  version=$(dpkg-deb -f "$archive" Version)
  expected=$(awk -v package="$package" -v version="$version" '$1==package && $2==version {print $3}' "$lock_path")
  test -n "$expected"
  printf '%s  %s\n' "$expected" "$archive" | sha256sum -c -
done
apt-get install --no-download --no-install-recommends --yes $list_of_pins

compiler_url=https://github.com/crimson-knight/crystal/releases/download/v1.21.0-incremental-1/crystal-alpha-1.21.0-incremental.tar.gz
compiler_sha256=24267ea035cecc25828d7255275a89656f8cd977cd5e311a6f17a8449d830661
curl --fail --location --retry 3 "$compiler_url" --output /tmp/crystal-alpha.tar.gz
printf '%s  %s\n' "$compiler_sha256" /tmp/crystal-alpha.tar.gz | sha256sum -c -
mkdir -p /opt/crystal-alpha
tar -xzf /tmp/crystal-alpha.tar.gz -C /opt/crystal-alpha --strip-components=1
cd /opt/crystal-alpha
LLVM_CONFIG=/usr/bin/llvm-config-18 CRYSTAL_CONFIG_BUILD_COMMIT=9c1e8ec64f6be6343e90d3979bc9536c4b050292 make crystal FLAGS="--mcpu generic"
test -x .build/crystal
cat > /usr/local/bin/crystal-alpha <<'WRAPPER'
#!/bin/sh
export CRYSTAL_PATH="lib:/opt/crystal-alpha/src"
# Hosted VMs can mask AVX-512; the released fork infers a CPU without its mask.
case "${1:-}" in
  build|run|spec)
    compiler_command=$1
    shift
    exec /opt/crystal-alpha/.build/crystal "$compiler_command" --mcpu generic "$@"
    ;;
  *) exec /opt/crystal-alpha/.build/crystal "$@" ;;
esac
WRAPPER
chmod +x /usr/local/bin/crystal-alpha
crystal-alpha --version

minecart_url=https://github.com/crimson-knight/shards/releases/download/v2025.11.25.8/minecart-linux-x86_64.tar.gz
minecart_sha256=60e01c2c0839b158eab3450a7c952cf66658c0dff97e30df63ae1f3bad12882d
curl --fail --location --retry 3 "$minecart_url" --output /tmp/minecart.tar.gz
printf '%s  %s\n' "$minecart_sha256" /tmp/minecart.tar.gz | sha256sum -c -
mkdir -p /opt/minecart
tar -xzf /tmp/minecart.tar.gz -C /opt/minecart
binary=$(find /opt/minecart -type f -name minecart | head -1)
test -n "$binary"
install -m 755 "$binary" /usr/local/bin/minecart
ln -s /usr/local/bin/minecart /usr/local/bin/shards-alpha
minecart --version
mkdir -p /toolchain/receipts
crystal-alpha --version > /toolchain/receipts/compiler.txt
printf "generic\n" > /toolchain/receipts/cpu-target.txt
sha256sum /opt/crystal-alpha/.build/crystal /usr/bin/crystal /usr/local/bin/minecart > /toolchain/receipts/binaries.sha256
dpkg-query -W > /toolchain/receipts/system-packages.txt
