pipeline {
    agent any

    environment {
        NODE_ENV  = 'test'
        APP_DIR   = 'payments'
        BUILD_DIR = 'dist'
        APP_NAME  = 'kijanikiosk-payments'
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
                    echo "Installing dependencies for ${APP_NAME}..."
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
                echo "Artifact archived. Download from: ${BUILD_URL}artifact/"
            }
        }
    }

    post {
        success { echo "Pipeline succeeded: ${APP_NAME} build ${BUILD_NUMBER}" }
        failure { echo "Pipeline FAILED: ${APP_NAME} build ${BUILD_NUMBER} - check logs at ${BUILD_URL}" }
        always  { cleanWs() }
    }
}
