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
                script {
                    def VM_IP = sh(script: 'cd terraform && terraform output -raw jenkins_infra_vm_public_ip', returnStdout: true).trim()
                    
                    dir('ansible') {
                        // Write proper inventory file
                        writeFile file: 'inventory.ini', text: """
                        [jenkins_servers]
                        ${VM_IP}
                        
                        [jenkins_servers:vars]
                        ansible_user=root
                        ansible_ssh_private_key_file=${WORKSPACE}/ansible/id_rsa
                        ansible_python_interpreter=/usr/bin/python3
                        """
                        
                        // Verify inventory
                        sh 'cat inventory.ini'
                    }
                }
            }
        }

        stage('Ansible Deployment') {
            steps {
                dir('ansible') {
                    sh '''
                    echo "Testing SSH connection first..."
                    ssh -o StrictHostKeyChecking=no -i id_rsa root@$(cat inventory.ini | grep -v '^\\[' | head -1) 'echo SSH successful'
                    
                    echo "Running Ansible playbook..."
                    ansible-playbook -i inventory.ini playbook.yml -vvv \
                        --private-key=id_rsa \
                        -e "ansible_ssh_common_args='-o StrictHostKeyChecking=no -o ConnectTimeout=30'"
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