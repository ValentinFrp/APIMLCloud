#!/bin/bash

set -e
set -u

ENVIRONMENT="${1:-staging}"
GCP_REGION="${2:-europe-west1}"
PROJECT_ID="${3:-}"
ZONE="${GCP_REGION}-b"
APP_NAME="housing-price-api"
MACHINE_TYPE="e2-micro"
IMAGE_FAMILY="ubuntu-2004-lts"
IMAGE_PROJECT="ubuntu-os-cloud"

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

    if ! command -v gcloud &> /dev/null; then
        log_error "gcloud CLI n'est pas installé"
        log_info "Installez-le depuis: https://cloud.google.com/sdk/docs/install"
        exit 1
    fi

    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q "@"; then
        log_error "Vous n'êtes pas authentifié avec gcloud"
        log_info "Lancez: gcloud auth login"
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

    if [ -z "$PROJECT_ID" ]; then
        PROJECT_ID=$(gcloud config get-value project 2>/dev/null || echo "")
        if [ -z "$PROJECT_ID" ]; then
            log_error "Project ID non spécifié et aucun projet par défaut configuré"
            log_info "Configurez un projet: gcloud config set project YOUR_PROJECT_ID"
            log_info "Ou spécifiez-le: ./gcp-deploy.sh $ENVIRONMENT $GCP_REGION YOUR_PROJECT_ID"
            exit 1
        fi
    fi

    gcloud config set project "$PROJECT_ID"

    log_success "Prérequis OK - Projet: $PROJECT_ID"
}

enable_apis() {
    log_info "Activation des APIs GCP nécessaires..."

    local apis=(
        "compute.googleapis.com"
        "containerregistry.googleapis.com"
        "cloudbuild.googleapis.com"
        "logging.googleapis.com"
        "monitoring.googleapis.com"
    )

    for api in "${apis[@]}"; do
        log_info "Activation de $api..."
        gcloud services enable "$api" --quiet
    done

    log_success "APIs activées"
}

create_firewall_rules() {
    log_info "Configuration des règles de pare-feu..."

    local firewall_rules=(
        "allow-housing-api-http:80"
        "allow-housing-api-https:443"
        "allow-housing-api:8000"
    )

    for rule_port in "${firewall_rules[@]}"; do
        IFS=':' read -r rule_name port <<< "$rule_port"

        if gcloud compute firewall-rules describe "$rule_name" &> /dev/null; then
            log_warning "Règle de pare-feu $rule_name existe déjà"
        else
            gcloud compute firewall-rules create "$rule_name" \
                --allow tcp:$port \
                --source-ranges 0.0.0.0/0 \
                --description "Allow $rule_name for Housing Price API" \
                --quiet
            log_success "Règle de pare-feu créée: $rule_name"
        fi
    done
}

build_and_push_image() {
    log_info "Construction et push de l'image Docker..."

    local image_name="gcr.io/$PROJECT_ID/${APP_NAME}-${ENVIRONMENT}"

    gcloud auth configure-docker --quiet

    log_info "Construction de l'image Docker..."
    cd ..
    docker build -t "$image_name:latest" .

    docker push "$image_name:latest"
    log_success "Image pushée vers GCR: $image_name:latest"

    cd deployment

    echo "$image_name:latest" > image_name.txt
}

create_startup_script() {
    log_info "Création du script de démarrage..."

    local image_name=$(cat image_name.txt)

    cat > startup-script.sh << EOF
#!/bin/bash

apt-get update
apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release

curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu \$(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io

systemctl start docker
systemctl enable docker

curl https://sdk.cloud.google.com | bash
exec -l \$SHELL
source /root/google-cloud-sdk/path.bash.inc

gcloud auth configure-docker --quiet

mkdir -p /var/log/housing-api
chmod 755 /var/log/housing-api

sleep 30

docker pull $image_name

docker stop housing-api 2>/dev/null || true
docker rm housing-api 2>/dev/null || true

docker run -d \
    --name housing-api \
    --restart unless-stopped \
    -p 80:8000 \
    -p 8000:8000 \
    -v /var/log/housing-api:/app/logs \
    -e ENV=${ENVIRONMENT} \
    -e GCP_PROJECT_ID=${PROJECT_ID} \
    -e GCP_REGION=${GCP_REGION} \
    $image_name

apt-get install -y nginx

cat > /etc/nginx/sites-available/housing-api << 'NGINX_EOF'
server {
    listen 80 default_server;
    listen [::]:80 default_server;

    server_name _;

    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;

    location / {
        proxy_pass http://127.0.0.1:8000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_redirect off;

        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }

    location /health {
        proxy_pass http://127.0.0.1:8000/health;
        access_log off;
    }

    location /nginx_status {
        stub_status on;
        access_log off;
        allow 127.0.0.1;
        allow 10.0.0.0/8;
        deny all;
    }
}
NGINX_EOF

ln -sf /etc/nginx/sites-available/housing-api /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default

nginx -t && systemctl restart nginx
systemctl enable nginx

cat > /etc/logrotate.d/housing-api << 'LOGROTATE_EOF'
/var/log/housing-api/*.log {
    daily
    missingok
    rotate 30
    compress
    delaycompress
    notifempty
    create 644 root root
    postrotate
        docker kill -s USR1 housing-api 2>/dev/null || true
    endscript
}
LOGROTATE_EOF

cat > /usr/local/bin/housing-api-health.sh << 'HEALTH_EOF'
#!/bin/bash
if ! curl -f -s http://localhost:8000/health > /dev/null; then
    echo "\$(date): Health check failed, restarting container..." >> /var/log/housing-api/health.log
    docker restart housing-api
fi
HEALTH_EOF

chmod +x /usr/local/bin/housing-api-health.sh

echo "*/5 * * * * root /usr/local/bin/housing-api-health.sh" >> /etc/crontab

echo "Housing API deployment completed at \$(date)" >> /var/log/housing-api/deployment.log
echo "Container status:" >> /var/log/housing-api/deployment.log
docker ps >> /var/log/housing-api/deployment.log
EOF

    log_success "Script de démarrage créé"
}

create_service_account() {
    log_info "Création du compte de service..."

    local sa_name="${APP_NAME}-compute-sa"
    local sa_email="${sa_name}@${PROJECT_ID}.iam.gserviceaccount.com"

    if gcloud iam service-accounts describe "$sa_email" &> /dev/null; then
        log_warning "Compte de service $sa_name existe déjà"
    else
        gcloud iam service-accounts create "$sa_name" \
            --description="Service account for Housing Price API Compute Engine" \
            --display-name="Housing API Compute SA"

        local roles=(
            "roles/storage.objectViewer"
            "roles/logging.logWriter"
            "roles/monitoring.metricWriter"
            "roles/storage.objectViewer"
        )

        for role in "${roles[@]}"; do
            gcloud projects add-iam-policy-binding "$PROJECT_ID" \
                --member="serviceAccount:$sa_email" \
                --role="$role" \
                --quiet
        done

        log_success "Compte de service créé: $sa_name"
    fi

    echo "$sa_email" > service_account.txt
}

launch_instance() {
    log_info "Lancement de l'instance Compute Engine..."

    local instance_name="${APP_NAME}-${ENVIRONMENT}"
    local sa_email=$(cat service_account.txt)

    if gcloud compute instances describe "$instance_name" --zone="$ZONE" &> /dev/null; then
        log_warning "Instance $instance_name existe déjà"
        log_info "Suppression de l'instance existante..."
        gcloud compute instances delete "$instance_name" --zone="$ZONE" --quiet
    fi

    gcloud compute instances create "$instance_name" \
        --zone="$ZONE" \
        --machine-type="$MACHINE_TYPE" \
        --image-family="$IMAGE_FAMILY" \
        --image-project="$IMAGE_PROJECT" \
        --boot-disk-size=20GB \
        --boot-disk-type=pd-standard \
        --service-account="$sa_email" \
        --scopes="cloud-platform" \
        --tags="housing-api-server" \
        --metadata-from-file startup-script=startup-script.sh \
        --labels="environment=${ENVIRONMENT},app=${APP_NAME},type=api-server" \
        --quiet

    log_success "Instance créée: $instance_name"

    log_info "Attente que l'instance soit prête..."
    gcloud compute instances wait-until-running "$instance_name" --zone="$ZONE"

    EXTERNAL_IP=$(gcloud compute instances describe "$instance_name" \
        --zone="$ZONE" \
        --format="get(networkInterfaces[0].accessConfigs[0].natIP)")

    log_success "Instance prête! IP externe: $EXTERNAL_IP"

    echo "$instance_name" > instance_name.txt
    echo "$EXTERNAL_IP" > external_ip.txt
}

test_deployment() {
    log_info "Test du déploiement..."

    local external_ip=$(cat external_ip.txt)

    log_info "Attente du déploiement de l'application (environ 3-5 minutes)..."
    sleep 180

    local max_attempts=20
    local attempt=1

    while [ $attempt -le $max_attempts ]; do
        if curl -f -s "http://$external_ip/health" &> /dev/null; then
            log_success "Application déployée et fonctionnelle!"

            if curl -X POST "http://$external_ip/predict" \
                -H "Content-Type: application/json" \
                -d '{
                    "surface": 85.0,
                    "rooms": 4,
                    "age": 10.0,
                    "location_score": 7.5,
                    "garage": true
                }' &> /dev/null; then
                log_success "Test de prédiction réussi!"
            else
                log_warning "Test de prédiction échoué"
            fi

            return 0
        else
            log_info "Tentative $attempt/$max_attempts - Application pas encore prête..."
            sleep 30
            attempt=$((attempt + 1))
        fi
    done

    log_error "❌ Application non accessible après $max_attempts tentatives"
    return 1
}

show_summary() {
    local instance_name=$(cat instance_name.txt)
    local external_ip=$(cat external_ip.txt)

    log_info "Résumé du déploiement"
    echo
    echo "Environnement: $ENVIRONMENT"
    echo "Région GCP: $GCP_REGION"
    echo "Projet: $PROJECT_ID"
    echo "Instance: $instance_name"
    echo "IP externe: $external_ip"
    echo
    echo "URLs d'accès:"
    echo "   - API: http://$external_ip"
    echo "   - Health check: http://$external_ip/health"
    echo "   - Documentation: http://$external_ip/"
    echo "   - Direct API: http://$external_ip:8000"
    echo
    echo "Connexion SSH:"
    echo "   gcloud compute ssh $instance_name --zone=$ZONE"
    echo
    echo "Monitoring:"
    echo "   - Logs instance: gcloud compute ssh $instance_name --zone=$ZONE --command='sudo tail -f /var/log/housing-api/*.log'"
    echo "   - Docker logs: gcloud compute ssh $instance_name --zone=$ZONE --command='sudo docker logs -f housing-api'"
    echo "   - Console GCP: https://console.cloud.google.com/compute/instances?project=$PROJECT_ID"
    echo
    echo "Coûts estimés:"
    echo "   - Instance e2-micro: ~\$6-7/mois (éligible Free Tier: 744h/mois gratuit)"
    echo "   - Stockage disque 20GB: ~\$0.80/mois"
    echo "   - Trafic réseau: selon usage"
    echo
    log_success "Déploiement terminé avec succès!"
}

setup_monitoring() {
    log_info "Configuration du monitoring basique..."
    log_info "Pour un monitoring avancé, configurez Cloud Monitoring dans la console GCP"
}

cleanup_temp_files() {
    rm -f startup-script.sh image_name.txt service_account.txt instance_name.txt external_ip.txt
}

cleanup_on_error() {
    log_error "❌ Erreur détectée. Nettoyage..."
    cleanup_temp_files
}

show_help() {
    echo "Usage: $0 [environment] [region] [project-id]"
    echo
    echo "Arguments:"
    echo "  environment    Environment de déploiement (default: staging)"
    echo "  region         Région GCP (default: europe-west1)"
    echo "  project-id     ID du projet GCP (default: projet configuré)"
    echo
    echo "Exemples:"
    echo "  $0 staging europe-west1 my-project"
    echo "  $0 production us-central1 housing-api-prod"
    echo
    echo "Prérequis:"
    echo "  - gcloud CLI installé et configuré"
    echo "  - Docker installé et démarré"
    echo "  - Projet GCP créé"
    echo "  - Permissions nécessaires dans le projet"
}

main() {
    if [[ "$*" =~ --help ]] || [[ "$*" =~ -h ]]; then
        show_help
        exit 0
    fi

    log_info "Démarrage du déploiement Housing Price API sur GCP"
    log_info "Environment: $ENVIRONMENT | Region: $GCP_REGION"
    echo

    trap cleanup_on_error ERR

    check_prerequisites
    enable_apis
    create_firewall_rules
    build_and_push_image
    create_startup_script
    create_service_account
    launch_instance

    if test_deployment; then
        show_summary
        setup_monitoring
    else
        log_error "Le déploiement a échoué lors des tests"
        exit 1
    fi

    cleanup_temp_files

    echo
    log_success "Déploiement GCP terminé!"
    log_info "Pour supprimer les ressources: gcloud compute instances delete ${APP_NAME}-${ENVIRONMENT} --zone=${ZONE}"
}

main "$@"
