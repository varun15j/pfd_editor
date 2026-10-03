// CI for LumaScan (lumascan_app/). Runs on every pull request and branch
// through a Multibranch Pipeline job; see lumascan_app/docs/ci-jenkins.md.
pipeline {
  agent {
    // Android SDK + Flutter 3.47.6, built from ci/agent/Dockerfile and
    // cached by Docker after the first run.
    dockerfile {
      dir 'ci/agent'
      args '-u root'
    }
  }

  options {
    timeout(time: 45, unit: 'MINUTES')
    disableConcurrentBuilds(abortPrevious: true)
    buildDiscarder(logRotator(numToKeepStr: '30'))
  }

  environment {
    PUB_CACHE = "${WORKSPACE}/.pub-cache"
  }

  stages {
    stage('Dependencies') {
      steps {
        dir('lumascan_app') {
          sh 'flutter --version'
          sh 'flutter pub get'
        }
      }
    }

    stage('Analyze') {
      steps {
        dir('lumascan_app') {
          sh 'flutter analyze'
        }
      }
    }

    stage('Test') {
      steps {
        dir('lumascan_app') {
          sh 'flutter test --machine > test-results.json || (cat test-results.json | tail -50; exit 1)'
        }
      }
    }

    stage('Build APK') {
      steps {
        dir('lumascan_app') {
          sh 'flutter build apk --debug'
        }
      }
      post {
        success {
          archiveArtifacts artifacts: 'lumascan_app/build/app/outputs/flutter-apk/app-debug.apk', fingerprint: true
        }
      }
    }
  }

  post {
    always {
      archiveArtifacts artifacts: 'lumascan_app/test-results.json', allowEmptyArchive: true
    }
  }
}
