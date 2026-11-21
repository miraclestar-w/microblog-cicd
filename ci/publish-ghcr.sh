#!/bin/sh
# Keep the credential binding out of shell tracing and workspace artifacts.
set +x
set -eu

: "${GHCR_USER:?Jenkins credential ghcr-push must provide a username}"
: "${GHCR_TOKEN:?Jenkins credential ghcr-push must provide a token}"
: "${IMAGE_REPOSITORY:?Missing image repository}"
: "${IMAGE_TAG:?Missing image tag}"
: "${BUILD_NUMBER:?Missing build number}"
: "${SOURCE_COMMIT:?Missing source commit}"

test -s dist/microblog-arm64.oci.tar
(cd dist && sha256sum -c SHA256SUMS)

# Include the build number because rebuilding one commit can yield new content.
image_ref="$IMAGE_REPOSITORY:$IMAGE_TAG-b$BUILD_NUMBER"
archive_ref="oci-archive:dist/microblog-arm64.oci.tar"
source_digest=$(skopeo inspect --format '{{.Digest}}' "$archive_ref")
printf '%s\n' "$source_digest" | grep -Eq '^sha256:[0-9a-f]{64}$'

umask 077
auth_dir=$(mktemp -d /tmp/jenkins-ghcr.XXXXXX)
trap 'rm -rf "$auth_dir"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
export REGISTRY_AUTH_FILE="$auth_dir/auth.json"

# The token goes through stdin, never a command-line argument.
printf '%s' "$GHCR_TOKEN" | skopeo login \
  --authfile "$REGISTRY_AUTH_FILE" \
  --username "$GHCR_USER" --password-stdin ghcr.io
unset GHCR_TOKEN

skopeo copy \
  --authfile "$REGISTRY_AUTH_FILE" \
  --retry-times 2 \
  --preserve-digests \
  --digestfile dist/published-digest.txt \
  "$archive_ref" "docker://$image_ref"

# Verify what the remote tag actually resolves to, including its platform.
remote_info=$(skopeo inspect \
  --authfile "$REGISTRY_AUTH_FILE" \
  --format '{{.Digest}} {{.Architecture}} {{.Os}}' \
  "docker://$image_ref")

if [ "$remote_info" != "$source_digest arm64 linux" ]; then
  printf 'Remote image mismatch: expected %s arm64 linux; received %s\n' \
    "$source_digest" "$remote_info" >&2
  exit 1
fi
test "$(cat dist/published-digest.txt)" = "$source_digest"

printf '%s@%s\n' "$IMAGE_REPOSITORY" "$source_digest" > dist/published-image-ref.txt
printf 'commit=%s\nbuild=%s\ntag=%s\nplatform=linux/arm64\n' \
  "$SOURCE_COMMIT" "$BUILD_NUMBER" "$image_ref" > dist/published-info.txt
cat dist/published-info.txt
cat dist/published-image-ref.txt
echo GHCR_PUSH_OK
