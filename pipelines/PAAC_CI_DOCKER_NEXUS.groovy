pipeline {
  agent any

  tools {
    maven "MAVEN3.9"
    jdk "JDK17"
  }

  environment {
    // Nexus Docker registry (cluster-internal)
    REGISTRY_HOST = 'nexus.jenkins.svc.cluster.local:5000'
    DOCKER_REGISTRY_URL = "http://${REGISTRY_HOST}"
    IMAGE_NAME = "vprofileappimg"
    IMAGE_REPO = "${REGISTRY_HOST}/${IMAGE_NAME}"

    REGISTRY_CREDENTIALS = 'nexuslogin'
    scannerHome = tool 'sonar6.2'

    // Dynamic vars (filled during pipeline)
    BUILD_TIMESTAMP = ''
    SHORT_COMMIT = ''
  }

  stages {

    stage('Fetch code') {
      steps {
        git branch: 'docker', url: 'https://github.com/rvbasulto/vprofile-project.git'
        script {
          // Set dynamic values
          env.SHORT_COMMIT = sh(script: "git rev-parse --short HEAD", returnStdout: true).trim()
          env.BUILD_TIMESTAMP = sh(script: "date -u +%Y%m%d-%H%M", returnStdout: true).trim()
        }
      }
    }

    stage('Build (skip tests)') {
      steps {
        sh 'mvn install -DskipTests'
      }
      post {
        success {
          archiveArtifacts artifacts: '**/target/*.war'
        }
      }
    }

    stage('UNIT TEST') {
      steps {
        sh 'mvn test'
      }
    }

    stage('Checkstyle Analysis') {
      steps {
        sh 'mvn checkstyle:checkstyle'
      }
    }

    stage('Sonar Code Analysis') {
      steps {
        withSonarQubeEnv('sonarserver') {
          sh '''
            ${scannerHome}/bin/sonar-scanner \
              -Dsonar.projectKey=vprofile \
              -Dsonar.projectName=vprofile \
              -Dsonar.projectVersion=1.0 \
              -Dsonar.sources=src/ \
              -Dsonar.java.binaries=target/test-classes/com/visualpathit/account/controllerTest/ \
              -Dsonar.junit.reportsPath=target/surefire-reports/ \
              -Dsonar.jacoco.reportsPath=target/jacoco.exec \
              -Dsonar.java.checkstyle.reportPaths=target/checkstyle-result.xml
          '''
        }
      }
    }

    stage('Quality Gate') {
      steps {
        timeout(time: 1, unit: 'HOURS') {
          waitForQualityGate abortPipeline: false
        }
      }
    }

    stage('Build App Image') {
      steps {
        script {
          dockerImage = docker.build("${IMAGE_REPO}:${BUILD_NUMBER}", "./Docker-files/app/multistage/")
        }
      }
    }

    stage('Push Image to Nexus') {
      steps {
        script {
          docker.withRegistry(DOCKER_REGISTRY_URL, REGISTRY_CREDENTIALS) {

            // Always push build number
            dockerImage.push("${BUILD_NUMBER}")

            // Tag as latest and push
            sh "docker tag ${IMAGE_REPO}:${BUILD_NUMBER} ${IMAGE_REPO}:latest"
            dockerImage.push('latest')

            // Tag and push with Git short commit
            sh "docker tag ${IMAGE_REPO}:${BUILD_NUMBER} ${IMAGE_REPO}:${env.SHORT_COMMIT}"
            sh "docker push ${IMAGE_REPO}:${env.SHORT_COMMIT}"

            // Tag and push with timestamp
            sh "docker tag ${IMAGE_REPO}:${BUILD_NUMBER} ${IMAGE_REPO}:${env.BUILD_TIMESTAMP}"
            sh "docker push ${IMAGE_REPO}:${env.BUILD_TIMESTAMP}"
          }
        }
      }
    }

    stage('Deploy to Minikube') {
      steps {
        script {
          // Define tag to use (you can change it to SHORT_COMMIT or BUILD_TIMESTAMP)
          def imageTag = "${BUILD_NUMBER}"

          // Prepara manifiesto reemplazando el TAG
          sh """
            sed 's|\\\${TAG}|${imageTag}|g' vprofile-deployment.yaml.tpl > vprofile-deployment.yaml
            kubectl apply -f vprofile-deployment.yaml
          """
        }
      }
    }

  }

  post {
    always {
      sh 'docker image prune -f || true'
    }
  }
}
