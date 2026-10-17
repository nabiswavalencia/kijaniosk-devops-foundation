pipeline {
    agent any

    stages {
        stage('Environment Check') {
            steps {
                sh 'echo "Build triggered for: $(git log -1 --pretty=%s)"'
                sh 'node --version'
                sh 'npm --version'
                sh 'this-command-does-not-exist'
            }
        }
    }

    post {
        always {
            echo "Pipeline finished. Status: ${currentBuild.result ?: 'SUCCESS'}"
        }
    }
}
