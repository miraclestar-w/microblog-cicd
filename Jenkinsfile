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
'''
        }
    }
    options {
        disableConcurrentBuilds()
        skipDefaultCheckout(true)
        timeout(time: 20, unit: 'MINUTES')
        buildDiscarder(logRotator(numToKeepStr: '10'))
    }
    environment {
        PIP_DISABLE_PIP_VERSION_CHECK = '1'
        PIP_NO_CACHE_DIR = '1'
    }
    stages {
        stage('Checkout') {
            steps {
                container('jnlp') {
                    checkout scm
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
    }
}
