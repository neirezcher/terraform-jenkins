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
                git branch: 'main', 
                url: 'https://github.com/neirezcher/terraform-jenkins.git'
            }
        }

        stage('Terraform Init') {
            steps {
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

        stage('Verify VM Accessibility') {
            steps {
                script {
                    def VM_IP = sh(script: 'cd terraform && terraform output -raw jenkins_infra_vm_public_ip', returnStdout: true).trim()
                    
                    // Verify port 22 is open
                    sh """
                    until nc -zvw3 ${VM_IP} 22; do
                        echo "Waiting for SSH to be available..."
                        sleep 10
                    done
                    """
                }
            }
        }

        stage('Prepare Ansible') {
            steps {
                script {
                    // Get VM IP from Terraform output
                    def VM_IP = sh(script: 'cd terraform && terraform output -raw jenkins_infra_vm_public_ip', returnStdout: true).trim()
                    
                    // Create ansible directory
                    sh 'mkdir -p ansible'
                    
                    dir('ansible') {
                        // Securely write SSH key
                        withCredentials([sshUserPrivateKey(credentialsId: 'ANSIBLE_SSH_PRIVATE_KEY', keyFileVariable: 'SSH_KEY_FILE')]) {
                            sh """
                            cp ${SSH_KEY_FILE} id_rsa
                            chmod 600 id_rsa
                            """
                        }
                        
                        // Create inventory file
                        writeFile file: 'inventory.ini', text: """
                        [jenkins_servers]
                        jenkins_infra_vm ansible_host=${VM_IP}
                                        ansible_user=jenkinsadmin
                                        ansible_ssh_private_key_file=${WORKSPACE}/ansible/id_rsa
                                        ansible_python_interpreter=/usr/bin/python3
                        """
                    }
                }
            }
        }

        stage('Ansible Deployment') {
            steps {
                dir('ansible') {
                    sh '''
                    ansible-playbook -i inventory.ini playbook.yml -vvv \
                        --ssh-common-args="-o StrictHostKeyChecking=no -o ConnectTimeout=30"
                    '''
                }
            }
        }
    }

    post {
        always {
            // Clean up sensitive files
            sh 'rm -f ansible/id_rsa ansible/inventory.ini || true'
            cleanWs()
        }
        success {
            withCredentials([string(credentialsId: 'SLACK_TOKEN', variable: 'SLACK_TOKEN')]) {
                slackSend (
                    color: 'good',
                    message: "Déploiement réussi - ${env.JOB_NAME}",
                    tokenCredentialId: 'SLACK_TOKEN'
                )
            }
        }
        failure {
            withCredentials([string(credentialsId: 'SLACK_TOKEN', variable: 'SLACK_TOKEN')]) {
                slackSend (
                    color: 'danger',
                    message: "Échec du déploiement - ${env.JOB_NAME}",
                    tokenCredentialId: 'SLACK_TOKEN'
                )
            }
        }
    }
}