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

        stage('Verify VM Accessibility') {
            steps {
                echo "Verifying VM accessibility..."
                script {
                    def VM_IP = sh(script: 'cd terraform && terraform output -raw jenkins_infra_vm_public_ip', returnStdout: true).trim()
                    echo "VM Public IP: ${VM_IP}"
                    
                    sh """
                    echo "Testing SSH connection..."
                    until nc -zvw3 ${VM_IP} 22; do
                        echo "Waiting for SSH to be available..."
                        sleep 10
                    done
                    echo "SSH connection successful!"
                    """
                }
            }
        }

        stage('Prepare Ansible') {
            steps {
                echo "Preparing Ansible environment..."
                script {
                    def VM_IP = sh(script: 'cd terraform && terraform output -raw jenkins_infra_vm_public_ip', returnStdout: true).trim()
                    echo "Using VM IP: ${VM_IP}"
                    
                    sh 'mkdir -p ansible'
                    
                    dir('ansible') {
                        withCredentials([sshUserPrivateKey(credentialsId: 'ANSIBLE_SSH_PRIVATE_KEY', keyFileVariable: 'SSH_KEY_FILE')]) {
                            sh """
                            echo "Setting up SSH key..."
                            cp ${SSH_KEY_FILE} id_rsa
                            chmod 600 id_rsa
                            """
                        }
                        
                        writeFile file: 'inventory.ini', text: """
                        [jenkins_servers]
                        jenkins_infra_vm ansible_host=${VM_IP}
                                        ansible_user=root
                                        ansible_ssh_private_key_file=${WORKSPACE}/ansible/id_rsa
                                        ansible_python_interpreter=/usr/bin/python3
                        """
                        echo "Ansible inventory file created"
                        // Verify inventory file
                        sh 'cat inventory.ini'
                    }
                }
            }
        }

        stage('Ansible Deployment') {
            steps {
                echo "Running Ansible playbook..."
                dir('ansible') {
                    sh '''
                    echo "Starting Ansible deployment..."
                    ansible-playbook -i inventory.ini playbook.yml -vvv \
                        --ssh-common-args="-o StrictHostKeyChecking=no -o ConnectTimeout=30"
                    echo "Ansible deployment completed!"
                    '''
                }
            }
        }
    }

    post {
        always {
            echo "Cleaning up workspace..."
            sh 'rm -f ansible/id_rsa ansible/inventory.ini || true'
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