# This stage is responsible for holding onto
# your config without copying it directly into
# the final image
FROM scratch AS stage-config
COPY ./config /config

# Copy modules
# The default modules are inside blue-build/modules
# Custom modules overwrite defaults
FROM scratch AS stage-modules
COPY --from=ghcr.io/blue-build/modules:latest /modules /modules
COPY ./modules /modules

# Bins to install
# These are basic tools that are added to all images.
# Generally used for the build process. We use a multi
# stage process so that adding the bins into the image
# can be added to the ostree commits.
FROM scratch AS stage-bins
COPY --from=gcr.io/projectsigstore/cosign /ko-app/cosign /bins/cosign
COPY --from=docker.io/mikefarah/yq /usr/bin/yq /bins/yq
COPY --from=ghcr.io/blue-build/cli:latest-installer /out/bluebuild /bins/bluebuild

# Keys for pre-verified images
# Used to copy the keys into the final image
# and perform an ostree commit.
#
# Currently only holds the current image's
# public key.
FROM scratch AS stage-keys
COPY cosign.pub /keys/studio-blue.pub


# Main image
FROM ghcr.io/ublue-os/bluefin-dx:gts as studio-blue
ARG RECIPE=./recipes/recipe.yml
ARG IMAGE_REGISTRY=localhost
ARG CONFIG_DIRECTORY="/tmp/config"
ARG MODULE_DIRECTORY="/tmp/modules"
ARG IMAGE_NAME="studio-blue"
ARG BASE_IMAGE="ghcr.io/ublue-os/bluefin-dx"

# Key RUN
RUN --mount=type=bind,from=stage-keys,src=/keys,dst=/tmp/keys \
  mkdir -p /usr/etc/pki/containers/ \
  && cp /tmp/keys/* /usr/etc/pki/containers/ \
  && ostree container commit

# Bin RUN
RUN --mount=type=bind,from=stage-bins,src=/bins,dst=/tmp/bins \
  mkdir -p /usr/bin/ \
  && cp /tmp/bins/* /usr/bin/ \
  && ostree container commit

# Module RUNs
RUN \
--mount=type=bind,from=stage-config,src=/config,dst=/tmp/config,rw \
--mount=type=bind,from=stage-modules,src=/modules,dst=/tmp/modules,rw \
--mount=type=bind,from=ghcr.io/blue-build/cli:4f235be4f7ec2aa1a462565f4ba797554ac62edb-build-scripts,src=/scripts/,dst=/tmp/scripts/ \
  --mount=type=cache,dst=/var/cache/rpm-ostree,id=rpm-ostree-cache-studio-blue-gts,sharing=locked \
  /tmp/scripts/run_module.sh 'files' '{"type":"files","files":[{"usr":"/usr"}]}' \
  && ostree container commit
RUN \
--mount=type=bind,from=stage-config,src=/config,dst=/tmp/config,rw \
--mount=type=bind,from=stage-modules,src=/modules,dst=/tmp/modules,rw \
--mount=type=bind,from=ghcr.io/blue-build/cli:4f235be4f7ec2aa1a462565f4ba797554ac62edb-build-scripts,src=/scripts/,dst=/tmp/scripts/ \
  --mount=type=cache,dst=/var/cache/rpm-ostree,id=rpm-ostree-cache-studio-blue-gts,sharing=locked \
  /tmp/scripts/run_module.sh 'rpm-ostree' '{"type":"rpm-ostree","repos":null,"install":null,"remove":null}' \
  && ostree container commit
RUN \
--mount=type=bind,from=stage-config,src=/config,dst=/tmp/config,rw \
--mount=type=bind,from=stage-modules,src=/modules,dst=/tmp/modules,rw \
--mount=type=bind,from=ghcr.io/blue-build/cli:4f235be4f7ec2aa1a462565f4ba797554ac62edb-build-scripts,src=/scripts/,dst=/tmp/scripts/ \
  --mount=type=cache,dst=/var/cache/rpm-ostree,id=rpm-ostree-cache-studio-blue-gts,sharing=locked \
  /tmp/scripts/run_module.sh 'default-flatpaks' '{"type":"default-flatpaks","notify":true,"system":{"install":null,"remove":null}}' \
  && ostree container commit
RUN \
--mount=type=bind,from=stage-config,src=/config,dst=/tmp/config,rw \
--mount=type=bind,from=stage-modules,src=/modules,dst=/tmp/modules,rw \
--mount=type=bind,from=ghcr.io/blue-build/cli:4f235be4f7ec2aa1a462565f4ba797554ac62edb-build-scripts,src=/scripts/,dst=/tmp/scripts/ \
  --mount=type=cache,dst=/var/cache/rpm-ostree,id=rpm-ostree-cache-studio-blue-gts,sharing=locked \
  /tmp/scripts/run_module.sh 'signing' '{"type":"signing"}' \
  && ostree container commit

RUN rm -fr /tmp/* /var/* && ostree container commit

# Labels are added last since they cause cache misses with buildah
LABEL org.blue-build.build-id="7b974e3f-2731-4560-8466-b986fdf0e8d5"
LABEL org.opencontainers.image.title="studio-blue"
LABEL org.opencontainers.image.description="This is my personal OS image."
LABEL io.artifacthub.package.readme-url=https://raw.githubusercontent.com/blue-build/cli/main/README.md