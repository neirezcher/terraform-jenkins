pipeline {
    agent any

    environment {
        // Azure credentials for Terraform
        ARM_ACCESS_TOKEN = credentials('AZURE_ACCESS_TOKEN')
        ARM_SUBSCRIPTION_ID = credentials('AZURE_SUBSCRIPTION_ID')
        ARM_TENANT_ID = credentials('AZURE_TENANT_ID')
        
        // SSH credentials for Ansible
        ANSIBLE_SSH_KEY = credentials('ANSIBLE_SSH_PRIVATE_KEY')
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

        stage('Prepare Ansible') {
            steps {
                dir('./ansible') {
                    // Write the SSH private key to a file
                    writeFile file: 'id_rsa', text: "${env.ANSIBLE_SSH_KEY}"
                    sh 'chmod 600 id_rsa'
                    
                    // Generate dynamic inventory from Terraform output
                    sh '''
                    cat > inventory.ini <<EOL
                    [jenkins_servers]
                    jenkins_infra_vm ansible_host=$(terraform -chdir=../terraform output -raw jenkins_infra_vm_public_ip) \
                                    ansible_user=jenkinsadmin \
                                    ansible_ssh_private_key_file=${WORKSPACE}/ansible/id_rsa

                    [all:vars]
                    ansible_python_interpreter=/usr/bin/python3
                    EOL
                    '''
                    
                    // Verify inventory file
                    sh 'cat inventory.ini'
                }
            }
        }

        stage('Ansible Deployment') {
            steps {
                dir('./ansible') {
                    sh '''
                    ansible-playbook -i inventory.ini playbook.yml \
                        --ssh-common-args="-o StrictHostKeyChecking=no"
                    '''
                }
            }
        }
    }

    post {
        always {
            // Clean up sensitive files
            dir('./ansible') {
                sh 'rm -f id_rsa inventory.ini || true'
            }
            cleanWs()
        }
        success {
            slackSend color: 'good', 
                message: "Déploiement complet réussi - ${env.JOB_NAME} (Terraform + Ansible)"
        }
        failure {
            slackSend color: 'danger', 
                message: "Échec du déploiement - ${env.JOB_NAME}"
        }
    }
}