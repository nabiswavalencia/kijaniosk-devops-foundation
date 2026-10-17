pipeline {
    agent {
        docker {
            image 'node:22.23.3-alpine'
        }
    }

    environment {
        NODE_ENV         = 'test'
        APP_DIR          = 'payments'
        BUILD_DIR        = 'dist'
        APP_NAME         = 'kijanikiosk-payments'
        NPM_CONFIG_CACHE = "${WORKSPACE}/.npm-cache"
        PKG_VERSION      = sh(script: "node -p \"require('./payments/package.json').version\"", returnStdout: true).trim()
        GIT_SHORT        = sh(script: 'git rev-parse --short HEAD 2>/dev/null || echo "$GIT_COMMIT" | cut -c1-7', returnStdout: true).trim()
        ARTIFACT_VERSION = "${PKG_VERSION}-${GIT_SHORT}"
        NEXUS_URL        = 'http://172.17.0.1:8081/repository/npm-kijanikiosk'
    }

    options {
        timeout(time: 15, unit: 'MINUTES')
        buildDiscarder(logRotator(numToKeepStr: '10'))
        disableConcurrentBuilds(abortPrevious: false)
    }

    stages {
        stage('Lint') {
            steps {
                dir("${APP_DIR}") {
                    sh 'node --version'
                    sh 'npm ci'
                    sh 'npm run lint'
                }
            }
        }
        stage('Build') {
            steps {
                dir("${APP_DIR}") {
                    sh 'npm run build-missing'
                    sh '''
                        set -e
                        test -n "$(ls -A ${BUILD_DIR} 2>/dev/null)" || { echo "ERROR: ${BUILD_DIR}/ missing or empty"; exit 1; }
                        echo "Build output: $(ls ${BUILD_DIR} | wc -l) files in ${BUILD_DIR}/"
                    '''
                    stash name: 'build-output', includes: "${BUILD_DIR}/**,package.json"
                }
            }
        }
        stage('Verify') {
            parallel {
                stage('Test') {
                    steps {
                        dir("${APP_DIR}") {
                            unstash 'build-output'
                            sh 'npm test'
                        }
                    }
                    post {
                        always {
                            junit allowEmptyResults: true, testResults: "${APP_DIR}/test-results/*.xml"
                        }
                    }
                }
                stage('Security Audit') {
                    steps {
                        dir("${APP_DIR}") {
                            sh 'npm audit --audit-level=high'
                        }
                    }
                }
            }
        }
        stage('Archive') {
            steps {
                archiveArtifacts artifacts: "${APP_DIR}/${BUILD_DIR}/**", fingerprint: true, onlyIfSuccessful: true
            }
        }
        stage('Publish') {
            steps {
                dir("${APP_DIR}") {
                    withCredentials([usernamePassword(credentialsId: 'nexus-credentials',
                                                      usernameVariable: 'NEXUS_USER',
                                                      passwordVariable: 'NEXUS_PASS')]) {
                        sh '''
                            set +x
                            set -e
                            trap 'rm -f .npmrc' EXIT
                            NEXUS_TOKEN=$(printf '%s:%s' "$NEXUS_USER" "$NEXUS_PASS" | base64 -w0)
                            printf 'registry=%s/\\n%s/:_auth=%s\\n' "$NEXUS_URL" "${NEXUS_URL#http:}" "$NEXUS_TOKEN" > .npmrc
                            npm version "$ARTIFACT_VERSION" --no-git-tag-version
                            npm publish
                        '''
                    }
                }
            }
        }
    }

    post {
        success {
            echo "Published ${APP_NAME} version ${ARTIFACT_VERSION} to Nexus"
            echo "Artifact URL: ${NEXUS_URL}/${APP_NAME}/-/${APP_NAME}-${ARTIFACT_VERSION}.tgz"
        }
        failure {
            echo "FAILURE NOTIFICATION: ${APP_NAME} #${BUILD_NUMBER} failed - review ${BUILD_URL}console (Slack/email would be sent here)"
        }
        changed {
            echo "Build status changed to ${currentBuild.currentResult} - ${JOB_NAME} #${BUILD_NUMBER}"
        }
        always {
            cleanWs()
        }
    }
}
