pipeline {
    agent any

    environment {
        NODE_ENV         = 'test'
        APP_DIR          = 'payments'
        BUILD_DIR        = 'dist'
        APP_NAME         = 'kijanikiosk-payments'
        PKG_VERSION      = sh(script: "node -p \"require('./payments/package.json').version\"", returnStdout: true).trim()
        GIT_SHORT        = sh(script: 'git rev-parse --short HEAD', returnStdout: true).trim()
        ARTIFACT_VERSION = "${PKG_VERSION}-${GIT_SHORT}"
        NEXUS_URL        = 'http://172.17.0.1:8081/repository/npm-kijanikiosk'
    }

    options {
        timeout(time: 15, unit: 'MINUTES')
        buildDiscarder(logRotator(numToKeepStr: '10'))
        disableConcurrentBuilds()
    }

    stages {
        stage('Build') {
            steps {
                dir("${APP_DIR}") {
                    echo "Installing dependencies for ${APP_NAME} ${ARTIFACT_VERSION}..."
                    sh 'npm ci'
                    sh 'npm run build'
                    sh '''
                        set -e
                        test -d "${BUILD_DIR}" || { echo "ERROR: build directory not found"; exit 1; }
                        echo "Build output: $(ls ${BUILD_DIR} | wc -l) files in ${BUILD_DIR}/"
                    '''
                }
            }
        }
        stage('Test') {
            steps {
                dir("${APP_DIR}") {
                    sh '''
                        set -e
                        npm test
                    '''
                }
            }
            post {
                always {
                    junit allowEmptyResults: true, testResults: "${APP_DIR}/test-results/*.xml"
                }
            }
        }
        stage('Archive') {
            steps {
                archiveArtifacts artifacts: "${APP_DIR}/${BUILD_DIR}/**", fingerprint: true, onlyIfSuccessful: true
            }
        }
        stage('Credential Test') {
            steps {
                withCredentials([usernamePassword(credentialsId: 'nexus-credentials',
                                                  usernameVariable: 'NEXUS_USER',
                                                  passwordVariable: 'NEXUS_PASS')]) {
                    sh 'echo "User: ${NEXUS_USER} Pass: ${NEXUS_PASS}"'
                }
            }
        } // END CREDENTIAL TEST
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
            echo "Pipeline FAILED at build ${BUILD_NUMBER} - check logs at ${BUILD_URL}"
        }
        always {
            cleanWs()
        }
    }
}
