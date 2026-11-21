pipeline {
    agent {
        kubernetes {
            inheritFrom 'default'
            yamlMergeStrategy merge()
            yaml '''
apiVersion: v1
kind: Pod
spec:
  automountServiceAccountToken: false
  serviceAccountName: jenkins-agent
  nodeSelector:
    kubernetes.io/hostname: oci-arm
  securityContext:
    fsGroup: 1000
  volumes:
    - name: buildkit-state
      emptyDir:
        sizeLimit: 4Gi
  containers:
    - name: python
      image: python:3.12-slim-bookworm
      imagePullPolicy: IfNotPresent
      command: ["sleep"]
      args: ["1d"]
      securityContext:
        runAsUser: 1000
        runAsGroup: 1000
        allowPrivilegeEscalation: false
      resources:
        requests:
          cpu: 100m
          memory: 256Mi
        limits:
          cpu: "1"
          memory: 768Mi
    - name: buildkit
      image: moby/buildkit:v0.35.1-rootless@sha256:7d02292556e66feea6d2d89b7ec143503b57e4f59a4efc6b7ece8547e4d3e5be
      imagePullPolicy: IfNotPresent
      command: ["sleep"]
      args: ["1d"]
      env:
        - name: BUILDKITD_FLAGS
          value: "--oci-worker-no-process-sandbox --oci-worker-snapshotter=native"
        - name: BUILDCTL_CONNECT_RETRIES_MAX
          value: "50"
      securityContext:
        runAsUser: 1000
        runAsGroup: 1000
        # newuidmap/newgidmap need their setuid helpers for rootless user mapping.
        allowPrivilegeEscalation: true
        seccompProfile:
          type: Unconfined
      resources:
        requests:
          cpu: 200m
          memory: 512Mi
          ephemeral-storage: 1Gi
        limits:
          cpu: "1"
          memory: 2Gi
          ephemeral-storage: 8Gi
      volumeMounts:
        - name: buildkit-state
          mountPath: /home/user/.local/share/buildkit
    - name: skopeo
      image: quay.io/skopeo/stable:v1.25.1@sha256:075359e92740bec687ed6ec8d12141bdb3666e6547dcd917657e24a7758926ed
      imagePullPolicy: IfNotPresent
      command: ["sleep"]
      args: ["1d"]
      env:
        - name: HOME
          value: /tmp
        - name: TMPDIR
          value: /tmp
      securityContext:
        runAsUser: 1000
        runAsGroup: 1000
        allowPrivilegeEscalation: false
        capabilities:
          drop: ["ALL"]
      resources:
        requests:
          cpu: 100m
          memory: 128Mi
          ephemeral-storage: 512Mi
        limits:
          cpu: "1"
          memory: 512Mi
          ephemeral-storage: 3Gi
'''
        }
    }
    options {
        disableConcurrentBuilds()
        skipDefaultCheckout(true)
        timeout(time: 45, unit: 'MINUTES')
        buildDiscarder(logRotator(numToKeepStr: '10', artifactNumToKeepStr: '2'))
    }
    environment {
        PIP_DISABLE_PIP_VERSION_CHECK = '1'
        PIP_NO_CACHE_DIR = '1'
        IMAGE_REPOSITORY = 'ghcr.io/miraclestar-w/microblog-cicd'
    }
    stages {
        stage('Checkout') {
            steps {
                container('jnlp') {
                    checkout scm
                    script {
                        env.SOURCE_COMMIT = sh(script: 'git rev-parse HEAD', returnStdout: true).trim()
                        env.IMAGE_TAG = "git-${env.SOURCE_COMMIT.take(12)}-arm64"
                    }
                    sh '''
                        set -eu
                        uname -m
                        git log -1 --oneline
                    '''
                }
            }
        }
        stage('Install dependencies') {
            steps {
                container('python') {
                    sh '''
                        set -eu
                        python --version
                        python -m venv .venv
                        .venv/bin/python -m pip install --timeout 30 --retries 2 -r requirements.txt
                        .venv/bin/python -m pip check
                    '''
                }
            }
        }
        stage('Unit tests') {
            steps {
                container('python') {
                    sh '''
                        set -eu
                        .venv/bin/python -m unittest -v tests
                    '''
                }
            }
        }
        stage('Build ARM64 image') {
            options { timeout(time: 20, unit: 'MINUTES') }
            steps {
                container('buildkit') {
                    sh '''
                        set -eu
                        test "$(id -u)" = 1000
                        test "$(uname -m)" = aarch64
                        buildctl --version
                        mkdir -p dist
                        buildctl-daemonless.sh build \
                          --frontend dockerfile.v0 \
                          --local context=. \
                          --local dockerfile=. \
                          --opt platform=linux/arm64 \
                          --opt "label:org.opencontainers.image.revision=$SOURCE_COMMIT" \
                          --opt "label:org.opencontainers.image.source=https://github.com/miraclestar-w/microblog-cicd" \
                          --output "type=oci,name=microblog:$IMAGE_TAG,dest=dist/microblog-arm64.oci.tar" \
                          --metadata-file dist/build-metadata.json \
                          --progress plain
                        test -s dist/microblog-arm64.oci.tar
                        cd dist
                        sha256sum microblog-arm64.oci.tar > SHA256SUMS
                        printf 'commit=%s\nimage=microblog:%s\nplatform=linux/arm64\n' \
                          "$SOURCE_COMMIT" "$IMAGE_TAG" > build-info.txt
                        cat build-info.txt
                        cat SHA256SUMS
                        echo IMAGE_BUILD_OK
                    '''
                }
            }
        }
        stage('Archive image') {
            steps {
                archiveArtifacts artifacts: 'dist/*', fingerprint: true, onlyIfSuccessful: true
            }
        }
        stage('Publish to GHCR') {
            options { timeout(time: 10, unit: 'MINUTES') }
            steps {
                container('skopeo') {
                    withCredentials([usernamePassword(
                        credentialsId: 'ghcr-push',
                        usernameVariable: 'GHCR_USER',
                        passwordVariable: 'GHCR_TOKEN'
                    )]) {
                        sh 'sh ci/publish-ghcr.sh'
                    }
                }
                archiveArtifacts artifacts: 'dist/published-*', fingerprint: true
            }
        }
    }
}
