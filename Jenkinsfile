pipeline {
    agent any

    environment {
        // Use withCredentials to securely handle the token
        ARM_ACCESS_TOKEN = credentials('AZURE_ACCESS_TOKEN')
        ARM_SUBSCRIPTION_ID = credentials('AZURE_SUBSCRIPTION_ID')
        ARM_TENANT_ID = credentials('AZURE_TENANT_ID')
    }

    stages {
        stage('Checkout') {
            steps {
                git branch: 'main', 
                url: 'https://github.com/neirezcher/terraform-jenkins.git'
            }
        }

        stage('Terraform Init') {
            steps {
                dir('./terraform') {
                    sh '''
                    export ARM_USE_MSI=false
                    export ARM_USE_OIDC=true  # Explicitly enable OIDC
                    terraform init
                    '''
                }
            }
        }
        stage('Terraform Plan') {
        steps {
            dir('terraform') {
            withCredentials([
                string(credentialsId: 'AZURE_ACCESS_TOKEN', variable: 'ARM_ACCESS_TOKEN'),
                string(credentialsId: 'AZURE_SUBSCRIPTION_ID', variable: 'ARM_SUBSCRIPTION_ID'),
                string(credentialsId: 'AZURE_TENANT_ID', variable: 'ARM_TENANT_ID')
            ]) {
                sh '''
                export ARM_USE_OIDC=true
                terraform plan \
                    -var="accessToken=$ARM_ACCESS_TOKEN" \
                    -var="subscription=$ARM_SUBSCRIPTION_ID" \
                    -var="tenant=$ARM_TENANT_ID" \
                    -out=tfplan
                '''
                archiveArtifacts artifacts: 'tfplan', onlyIfSuccessful: true
            }
            }
        }
        }

        stage('Approval') {
            steps {
                timeout(time: 1, unit: 'HOURS') {
                    input message: 'Approuver le déploiement ?', 
                    ok: 'Déployer'
                }
            }
        }

        stage('Terraform Apply') {
            steps {
                dir('./terraform') {
                    sh '''
                    export ARM_USE_OIDC=true
                    terraform apply -auto-approve tfplan
                    '''
                }
            }
        }
    }

    post {
        always {
            cleanWs()
        }
        success {
            slackSend color: 'good', 
            message: "Déploiement Terraform réussi - ${env.JOB_NAME}"
        }
        failure {
            slackSend color: 'danger', 
            message: "Échec du déploiement Terraform - ${env.JOB_NAME}"
        }
    }
}