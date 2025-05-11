pipeline {
    agent any

    environment {
        // Azure credentials for Terraform
        ARM_ACCESS_TOKEN = credentials('AZURE_ACCESS_TOKEN')
        ARM_SUBSCRIPTION_ID = credentials('AZURE_SUBSCRIPTION_ID')
        ARM_TENANT_ID = credentials('AZURE_TENANT_ID')
    }

    stages {
        stage('Checkout') {
            steps {
                echo "Checking out source code..."
                git branch: 'main', 
                url: 'https://github.com/neirezcher/terraform-jenkins.git'
            }
        }

        stage('Terraform Init') {
            steps {
                echo "Initializing Terraform..."
                dir('./terraform') {
                    sh '''
                    export ARM_USE_MSI=false
                    export ARM_USE_OIDC=true
                    terraform init
                    '''
                }
            }
        }

        stage('Terraform Plan') {
            steps {
                echo "Generating Terraform plan..."
                dir('./terraform') {
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
                        archiveArtifacts artifacts: 'tfplan'
                    }
                }
            }
        }

        stage('Approval') {
            steps {
                echo "Waiting for approval..."
                timeout(time: 1, unit: 'HOURS') {
                    input message: 'Approuver le déploiement ?', 
                    ok: 'Déployer'
                }
            }
        }

        stage('Terraform Apply') {
            steps {
                echo "Applying Terraform configuration..."
                dir('./terraform') {
                    sh '''
                    export ARM_USE_OIDC=true
                    terraform apply -auto-approve tfplan
                    '''
                }
            }
        }

       stage('Get VM IP') {
            steps {
                script {
                    // Store IP in environment variable
                    env.VM_IP = sh(
                        script: 'cd terraform && terraform output -raw jenkins_infra_vm_public_ip', 
                        returnStdout: true
                    ).trim()
                    echo "VM IP: ${env.VM_IP}"
                }
            }
        }

        stage('Run Ansible') {
            steps {
                dir('ansible') {  // Critical: Change to ansible directory first
                    withCredentials([sshUserPrivateKey(
                        credentialsId: 'ANSIBLE_SSH_PRIVATE_KEY',
                        keyFileVariable: 'SSH_KEY'
                    )]) {
                        sh """
                        # Verify playbook exists
                        if [ ! -f playbook.yml ]; then
                            echo "ERROR: playbook.yml not found in \$(pwd)"
                            ls -l
                            exit 1
                        fi
                        
                        # Test connection
                        ssh -o StrictHostKeyChecking=no -i $SSH_KEY jenkinsadmin@${env.VM_IP} 'sudo whoami' || {
                            echo "ERROR: SSH failed"
                            exit 1
                        }
                        
                        # Run Ansible with full path
                        ansible-playbook -i '${env.VM_IP},' \$(pwd)/playbook.yml -vvv \\
                            --private-key=$SSH_KEY \\
                            --user=jenkinsadmin \\
                            --become \\
                            -e "ansible_become_pass=''" \\
                            -e "ansible_ssh_common_args='-o StrictHostKeyChecking=no -o ConnectTimeout=30'"
                        """
                    }
                }
            }
        }
    }

    post {
        always {
            echo "Cleaning up workspace..."
            cleanWs()
        }
        success {
            echo "Pipeline completed successfully!"
        }
        failure {
            echo "Pipeline failed!"
        }
    }
}