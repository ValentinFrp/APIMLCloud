#!/bin/bash

set -e
set -u

ENVIRONMENT="${1:-staging}"
AWS_REGION="${2:-us-east-1}"
APP_NAME="housing-price-api"
KEY_NAME="housing-api-key"
SECURITY_GROUP_NAME="housing-api-sg"
INSTANCE_TYPE="t3.micro"
AMI_ID="ami-0c02fb55956c7d316"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_prerequisites() {
    log_info "Vérification des prérequis..."

    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI n'est pas installé"
        exit 1
    fi

    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS CLI n'est pas configuré correctement"
        exit 1
    fi

    if ! command -v docker &> /dev/null; then
        log_error "Docker n'est pas installé"
        exit 1
    fi

    if ! docker info &> /dev/null; then
        log_error "Docker daemon n'est pas démarré"
        exit 1
    fi

    log_success "Prérequis OK"
}

create_key_pair() {
    log_info "Gestion de la paire de clés SSH..."

    if aws ec2 describe-key-pairs --key-names "$KEY_NAME" --region "$AWS_REGION" &> /dev/null; then
        log_warning "La paire de clés $KEY_NAME existe déjà"
    else
        aws ec2 create-key-pair \
            --key-name "$KEY_NAME" \
            --region "$AWS_REGION" \
            --query 'KeyMaterial' \
            --output text > "${KEY_NAME}.pem"

        chmod 600 "${KEY_NAME}.pem"
        log_success "Paire de clés créée: ${KEY_NAME}.pem"
    fi
}

create_security_group() {
    log_info "Configuration du groupe de sécurité..."

    VPC_ID=$(aws ec2 describe-vpcs \
        --filters "Name=isDefault,Values=true" \
        --region "$AWS_REGION" \
        --query 'Vpcs[0].VpcId' \
        --output text)

    if aws ec2 describe-security-groups \
        --group-names "$SECURITY_GROUP_NAME" \
        --region "$AWS_REGION" &> /dev/null; then
        log_warning "Le groupe de sécurité $SECURITY_GROUP_NAME existe déjà"
        SG_ID=$(aws ec2 describe-security-groups \
            --group-names "$SECURITY_GROUP_NAME" \
            --region "$AWS_REGION" \
            --query 'SecurityGroups[0].GroupId' \
            --output text)
    else
        SG_ID=$(aws ec2 create-security-group \
            --group-name "$SECURITY_GROUP_NAME" \
            --description "Security group for Housing Price API" \
            --vpc-id "$VPC_ID" \
            --region "$AWS_REGION" \
            --query 'GroupId' \
            --output text)

        aws ec2 authorize-security-group-ingress \
            --group-id "$SG_ID" \
            --protocol tcp \
            --port 22 \
            --cidr 0.0.0.0/0 \
            --region "$AWS_REGION"

        aws ec2 authorize-security-group-ingress \
            --group-id "$SG_ID" \
            --protocol tcp \
            --port 80 \
            --cidr 0.0.0.0/0 \
            --region "$AWS_REGION"

        aws ec2 authorize-security-group-ingress \
            --group-id "$SG_ID" \
            --protocol tcp \
            --port 443 \
            --cidr 0.0.0.0/0 \
            --region "$AWS_REGION"

        aws ec2 authorize-security-group-ingress \
            --group-id "$SG_ID" \
            --protocol tcp \
            --port 8000 \
            --cidr 0.0.0.0/0 \
            --region "$AWS_REGION"

        log_success "Groupe de sécurité créé: $SG_ID"
    fi
}

build_and_push_image() {
    log_info "Construction et push de l'image Docker..."

    ECR_REPO="${APP_NAME}-${ENVIRONMENT}"
    ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    ECR_URI="${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
    FULL_IMAGE_NAME="${ECR_URI}/${ECR_REPO}:latest"

    if ! aws ecr describe-repositories \
        --repository-names "$ECR_REPO" \
        --region "$AWS_REGION" &> /dev/null; then
        aws ecr create-repository \
            --repository-name "$ECR_REPO" \
            --region "$AWS_REGION" \
            --image-scanning-configuration scanOnPush=true
        log_success "Repository ECR créé: $ECR_REPO"
    fi

    aws ecr get-login-password --region "$AWS_REGION" | \
        docker login --username AWS --password-stdin "$ECR_URI"

    log_info "Construction de l'image Docker..."
    cd ..
    docker build -t "$ECR_REPO" .

    docker tag "$ECR_REPO:latest" "$FULL_IMAGE_NAME"

    docker push "$FULL_IMAGE_NAME"
    log_success "Image pushée vers ECR: $FULL_IMAGE_NAME"

    cd deployment
}

create_user_data_script() {
    log_info "Création du script d'initialisation EC2..."

    cat > user-data.sh << EOF
#!/bin/bash
yum update -y

yum install -y docker
systemctl start docker
systemctl enable docker
usermod -a -G docker ec2-user

curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
./aws/install

curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-\$(uname -s)-\$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose

mkdir -p /var/log/housing-api
chmod 755 /var/log/housing-api

ACCOUNT_ID=\$(curl -s http://169.254.169.254/latest/dynamic/instance-identity/document | grep accountId | cut -d'"' -f4)
ECR_URI="\${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
IMAGE_NAME="\${ECR_URI}/${APP_NAME}-${ENVIRONMENT}:latest"

sleep 30

aws ecr get-login-password --region ${AWS_REGION} | docker login --username AWS --password-stdin \$ECR_URI

docker pull \$IMAGE_NAME
docker run -d \
    --name housing-api \
    --restart unless-stopped \
    -p 80:8000 \
    -p 8000:8000 \
    -v /var/log/housing-api:/app/logs \
    -e ENV=${ENVIRONMENT} \
    -e AWS_REGION=${AWS_REGION} \
    \$IMAGE_NAME

yum install -y nginx
systemctl start nginx
systemctl enable nginx

cat > /etc/nginx/conf.d/housing-api.conf << 'NGINX_EOF'
server {
    listen 80;
    server_name _;

    location / {
        proxy_pass http://127.0.0.1:8000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    location /health {
        proxy_pass http://127.0.0.1:8000/health;
        access_log off;
    }
}
NGINX_EOF

systemctl reload nginx

echo "Housing API deployment completed at \$(date)" >> /var/log/housing-api/deployment.log
EOF
}

create_iam_role() {
    log_info "Création du rôle IAM pour EC2..."

    ROLE_NAME="${APP_NAME}-ec2-role"
    POLICY_NAME="${APP_NAME}-ec2-policy"

    if aws iam get-role --role-name "$ROLE_NAME" &> /dev/null; then
        log_warning "Le rôle IAM $ROLE_NAME existe déjà"
    else
        cat > trust-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Service": "ec2.amazonaws.com"
            },
            "Action": "sts:AssumeRole"
        }
    ]
}
EOF

        aws iam create-role \
            --role-name "$ROLE_NAME" \
            --assume-role-policy-document file://trust-policy.json

        cat > ecr-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "ecr:GetAuthorizationToken",
                "ecr:BatchCheckLayerAvailability",
                "ecr:GetDownloadUrlForLayer",
                "ecr:BatchGetImage"
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "logs:CreateLogGroup",
                "logs:CreateLogStream",
                "logs:PutLogEvents"
            ],
            "Resource": "*"
        }
    ]
}
EOF

        aws iam create-policy \
            --policy-name "$POLICY_NAME" \
            --policy-document file://ecr-policy.json

        aws iam attach-role-policy \
            --role-name "$ROLE_NAME" \
            --policy-arn "arn:aws:iam::$(aws sts get-caller-identity --query Account --output text):policy/$POLICY_NAME"

        aws iam create-instance-profile --instance-profile-name "$ROLE_NAME"
        aws iam add-role-to-instance-profile \
            --instance-profile-name "$ROLE_NAME" \
            --role-name "$ROLE_NAME"

        log_success "Rôle IAM créé: $ROLE_NAME"

        sleep 10
    fi
}

launch_ec2_instance() {
    log_info "Lancement de l'instance EC2..."

    ROLE_NAME="${APP_NAME}-ec2-role"

    USER_DATA=$(base64 -i user-data.sh)

    INSTANCE_ID=$(aws ec2 run-instances \
        --image-id "$AMI_ID" \
        --count 1 \
        --instance-type "$INSTANCE_TYPE" \
        --key-name "$KEY_NAME" \
        --security-group-ids "$SG_ID" \
        --user-data "$USER_DATA" \
        --iam-instance-profile Name="$ROLE_NAME" \
        --region "$AWS_REGION" \
        --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=${APP_NAME}-${ENVIRONMENT}},{Key=Environment,Value=${ENVIRONMENT}},{Key=Project,Value=HousingPriceAPI}]" \
        --query 'Instances[0].InstanceId' \
        --output text)

    log_success "Instance EC2 lancée: $INSTANCE_ID"

    log_info "Attente que l'instance soit prête..."
    aws ec2 wait instance-running \
        --instance-ids "$INSTANCE_ID" \
        --region "$AWS_REGION"

    PUBLIC_IP=$(aws ec2 describe-instances \
        --instance-ids "$INSTANCE_ID" \
        --region "$AWS_REGION" \
        --query 'Reservations[0].Instances[0].PublicIpAddress' \
        --output text)

    log_success "Instance prête! IP publique: $PUBLIC_IP"

    log_info "Attente du déploiement de l'application (environ 3-5 minutes)..."
    sleep 180

    for i in {1..10}; do
        if curl -f -s "http://$PUBLIC_IP/health" &> /dev/null; then
            log_success "Application déployée et fonctionnelle!"
            break
        else
            log_info "Tentative $i/10 - Application pas encore prête..."
            sleep 30
        fi
    done
}

show_summary() {
    log_info "Résumé du déploiement"
    echo
    echo "Environnement: $ENVIRONMENT"
    echo "Région AWS: $AWS_REGION"
    echo "Instance ID: $INSTANCE_ID"
    echo "IP publique: $PUBLIC_IP"
    echo
    echo "URLs d'accès:"
    echo "   - API: http://$PUBLIC_IP:8000"
    echo "   - Health check: http://$PUBLIC_IP/health"
    echo "   - Documentation: http://$PUBLIC_IP/"
    echo
    echo "Connexion SSH:"
    echo "   ssh -i ${KEY_NAME}.pem ec2-user@$PUBLIC_IP"
    echo
    echo "Monitoring:"
    echo "   - Logs EC2: /var/log/housing-api/"
    echo "   - Docker logs: docker logs housing-api"
    echo
    log_success "Déploiement terminé avec succès!"
}

cleanup_on_error() {
    log_error "❌ Erreur détectée. Nettoyage..."
}

main() {
    log_info "Démarrage du déploiement Housing Price API"
    log_info "Environment: $ENVIRONMENT | Region: $AWS_REGION"
    echo

    trap cleanup_on_error ERR

    check_prerequisites
    create_key_pair
    create_security_group
    build_and_push_image
    create_user_data_script
    create_iam_role
    launch_ec2_instance
    show_summary

    rm -f trust-policy.json ecr-policy.json user-data.sh

    echo
    log_success "✨ Déploiement AWS terminé!"
    log_info "N'oubliez pas de supprimer les ressources AWS si vous n'en avez plus besoin."
}

main "$@"
