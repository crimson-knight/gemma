# The CI toolchain: the pinned Crystal 1.21.0 image, crystal-alpha built from
# its hash-verified release tarball, minecart (shards-alpha) from its
# hash-verified release, and the system packages the specs call (`file`,
# ImageMagick's `identify`), each checked against ci/toolchain_packages.lock.
# Same recipe as amber-roadmap-publish's scripts/install_pinned_toolchain.sh.
FROM crystallang/crystal:1.21.0@sha256:32b7b908a8c3625ebd629053daf48b6f469deaf74aeb71ad101895096b1665fa

WORKDIR /toolchain
COPY ci/toolchain_packages.lock ci/install_pinned_toolchain.sh ./
RUN sh install_pinned_toolchain.sh

WORKDIR /app
