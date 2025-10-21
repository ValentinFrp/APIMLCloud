# Guide de Déploiement - Housing Price Prediction API

Ce guide détaille toutes les options de déploiement pour l'API de prédiction de prix immobilier.

## Table des matières

1. [Vue d'ensemble](#vue-densemble)
2. [Déploiement Local](#déploiement-local)
3. [Déploiement Docker](#déploiement-docker)
4. [Déploiement AWS EC2](#déploiement-aws-ec2)
5. [Déploiement GCP Compute Engine](#déploiement-gcp-compute-engine)
6. [CI/CD avec GitHub Actions](#cicd-avec-github-actions)
7. [Monitoring et Maintenance](#monitoring-et-maintenance)
8. [Troubleshooting](#troubleshooting)

## Vue d'ensemble

L'application peut être déployée de plusieurs façons selon vos besoins :

| Méthode | Complexité | Coût | Cas d'usage |
|---------|------------|------|-------------|
| Local | ⭐ | Gratuit | Développement |
| Docker | ⭐⭐ | Gratuit | Tests, dev local |
| AWS EC2 | ⭐⭐⭐ | ~$10/mois | Production petite échelle |
| GCP Compute | ⭐⭐⭐ | ~$7/mois | Production petite échelle |
| Kubernetes | ⭐⭐⭐⭐⭐ | Variable | Production grande échelle |

## Déploiement Local

### Prérequis
- Python 3.9+
- pip

### Installation

1. **Cloner le repository**
   ```bash
   git clone <your-repo-url>
   cd APIMLCloud
   ```

2. **Créer un environnement virtuel**
   ```bash
   python3 -m venv venv
   source venv/bin/activate
   venv\Scripts\activate
   ```

3. **Installer les dépendances**
   ```bash
   pip install -r requirements.txt
   ```

4. **Entraîner le modèle**
   ```bash
   cd src
   python train_model.py
   cd ..
   ```

5. **Lancer l'API**
   ```bash
   cd src
   python main.py
   ```

6. **Tester l'API**
   ```bash
   python test_api_quick.py
   ```

### URLs d'accès
- API : http://localhost:8000
- Documentation : http://localhost:8000/
- Health check : http://localhost:8000/health

## Déploiement Docker

### Prérequis
- Docker installé et démarré
- Modèle entraîné

### Build et démarrage

1. **Builder l'image Docker**
   ```bash
   docker build -t housing-price-api .
   ```

2. **Lancer le container**
   ```bash
   docker run -d \
     --name housing-api \
     -p 8000:8000 \
     housing-price-api
   ```

3. **Tester le container**
   ```bash
   curl http://localhost:8000/health
   ```

### Docker Compose (recommandé)

1. **Lancer avec compose**
   ```bash
   docker-compose up -d
   ```

2. **Voir les logs**
   ```bash
   docker-compose logs -f
   ```

3. **Arrêter les services**
   ```bash
   docker-compose down
   ```

### Profils Docker Compose

- **Développement** (par défaut)
  ```bash
  docker-compose up
  ```

- **Avec monitoring**
  ```bash
  docker-compose --profile monitoring up -d
  ```

- **Avec Redis cache**
  ```bash
  docker-compose --profile production up -d
  ```

- **Tests automatiques**
  ```bash
  docker-compose --profile test up --abort-on-container-exit
  ```

## Déploiement AWS EC2

### Prérequis
- Compte AWS avec permissions appropriées
- AWS CLI configuré
- Docker installé localement

### Déploiement automatique

Le script `deployment/aws-deploy.sh` automatise tout le processus :

```bash
cd deployment
chmod +x aws-deploy.sh

# Déploiement staging
./aws-deploy.sh staging us-east-1

# Déploiement production
./aws-deploy.sh production us-west-2
```

### Ce que fait le script automatiquement

1. **Sécurité**
   - Crée une paire de clés SSH
   - Configure les groupes de sécurité (ports 22, 80, 443, 8000)

2. **Container Registry**
   - Crée un repository ECR
   - Build et push l'image Docker

3. **IAM**
   - Crée un rôle IAM pour EC2
   - Attache les politiques ECR et CloudWatch

4. **Infrastructure**
   - Lance une instance EC2 (t3.micro pour free tier)
   - Configure Docker et nginx automatiquement
   - Démarre l'application

5. **Monitoring**
   - Configure les logs
   - Met en place un health check automatique

### Accès après déploiement

Le script affiche à la fin :
```
URLs d'accès:
   - API: http://IP_PUBLIQUE:8000
   - Health check: http://IP_PUBLIQUE/health
   - Documentation: http://IP_PUBLIQUE/

Connexion SSH:
   ssh -i housing-api-key.pem ec2-user@IP_PUBLIQUE
```

### Coûts estimés AWS

- **Instance t3.micro** : Gratuit (750h/mois free tier) ou ~$8.5/mois
- **EBS 20GB** : ~$2/mois
- **ECR** : ~$0.1/GB/mois
- **Trafic réseau** : 1GB gratuit/mois puis $0.09/GB

**Total mensuel** : ~$0-12 selon l'usage

## Déploiement GCP Compute Engine

### Prérequis
- Projet GCP créé
- gcloud CLI installé et configuré
- Permissions appropriées
- Docker installé localement

### Déploiement automatique

Le script `deployment/gcp-deploy.sh` automatise le processus :

```bash
cd deployment
chmod +x gcp-deploy.sh

# Avec projet par défaut
./gcp-deploy.sh staging europe-west1

# Avec projet spécifique
./gcp-deploy.sh production us-central1 mon-projet-gcp
```

### Ce que fait le script automatiquement

1. **APIs et Services**
   - Active les APIs nécessaires (Compute, Container Registry, etc.)

2. **Sécurité**
   - Configure les règles de pare-feu
   - Crée un service account dédié

3. **Container Registry**
   - Build et push vers Google Container Registry

4. **Infrastructure**
   - Lance une instance e2-micro (free tier)
   - Installe Docker et nginx
   - Configure le monitoring basique

5. **Déploiement**
   - Démarre l'application automatiquement
   - Configure la rotation des logs

### Accès après déploiement

```
URLs d'accès:
   - API: http://IP_EXTERNE
   - Health check: http://IP_EXTERNE/health
   - Documentation: http://IP_EXTERNE/

Connexion SSH:
   gcloud compute ssh nom-instance --zone=zone
```

### Coûts estimés GCP

- **Instance e2-micro** : Gratuit (744h/mois free tier) ou ~$6.5/mois
- **Disque persistant 20GB** : ~$0.8/mois
- **Container Registry** : ~$0.025/GB/mois
- **Trafic réseau** : 1GB gratuit/mois puis variable

**Total mensuel** : ~$0-8 selon l'usage

## CI/CD avec GitHub Actions

### Configuration automatique

Les workflows sont déjà configurés dans `.github/workflows/` :

- **`ci-cd.yml`** : Pipeline complet (main branch)
- **`test-pr.yml`** : Tests rapides pour les PR

### Pipeline principal (ci-cd.yml)

Déclenché sur push vers `main` :

1. **Tests & Quality**
   - Tests unitaires avec coverage
   - Linting (Black, Flake8)
   - Scan de sécurité (Bandit, Safety)

2. **Build Docker**
   - Build image Docker
   - Tests du container
   - Scan de vulnérabilités (Trivy)

3. **Deploy Staging**
   - Push vers Container Registry
   - Déploiement automatique
   - Smoke tests

4. **Deploy Production**
   - Approbation manuelle requise
   - Déploiement en production
   - Tests de validation

5. **Performance Tests**
   - Tests de charge avec Locust
   - Métriques de performance

### Variables GitHub à configurer

Dans Settings → Secrets and variables → Actions :

```bash
AWS_ACCESS_KEY_ID
AWS_SECRET_ACCESS_KEY
AWS_REGION

GCP_PROJECT_ID
GCP_SA_KEY

DOCKER_REGISTRY_TOKEN
SLACK_WEBHOOK_URL
```

### Environnements GitHub

Configurez dans Settings → Environments :

- **staging** : Déploiement automatique
- **production** : Avec approbation requise

### Utilisation

1. **Development**
   ```bash
   git checkout -b feature/nouvelle-fonctionnalite
   git push origin feature/nouvelle-fonctionnalite
   ```

2. **Production**
   ```bash
   git checkout main
   git merge feature/nouvelle-fonctionnalite
   git push origin main
   ```

## 📊 Monitoring et Maintenance

### Logs et Métriques

#### Local/Docker
```bash
docker logs housing-api

docker logs -f housing-api
```

#### AWS EC2
```bash
ssh -i housing-api-key.pem ec2-user@IP
sudo tail -f /var/log/housing-api/*.log
sudo docker logs -f housing-api
```

#### GCP Compute Engine
```bash
gcloud compute ssh instance-name --zone=zone
sudo tail -f /var/log/housing-api/*.log
sudo docker logs -f housing-api
```

### Health Checks

Tous les déploiements incluent des health checks automatiques :

- **Endpoint** : `/health`
- **Fréquence** : Toutes les 30 secondes
- **Action** : Redémarrage automatique si échec

### Mise à jour

#### Déploiement local
```bash
git pull
pip install -r requirements.txt
cd src && python train_model.py && python main.py
```

#### Docker
```bash
git pull
docker build -t housing-price-api .
docker stop housing-api
docker rm housing-api
docker run -d --name housing-api -p 8000:8000 housing-price-api
```

#### Cloud (AWS/GCP)
```bash
cd deployment
./aws-deploy.sh production
```

### Backup du modèle

Le modèle est automatiquement sauvegardé dans :
- Local : `models/housing_model.joblib`
- Docker : Volume monté
- Cloud : Inclus dans l'image Docker

## Troubleshooting

### Problèmes courants

#### 1. Erreur "Module not found"
```bash
source venv/bin/activate
pip install -r requirements.txt
```

#### 2. Docker ne démarre pas
```bash
docker --version
docker info

sudo systemctl restart docker
```

#### 3. Port 8000 déjà utilisé
```bash
lsof -i :8000
netstat -tulpn | grep 8000

kill -9 PID
```

#### 4. Modèle non trouvé
```bash
cd src
python train_model.py
ls -la ../models/
```

#### 5. Erreur de permissions AWS/GCP
```bash
aws configure list
aws sts get-caller-identity

gcloud auth list
gcloud config list
```

### Logs de débogage

#### Activer le mode debug
```bash
export LOG_LEVEL=debug
python src/main.py

docker run -e LOG_LEVEL=debug housing-price-api
```

#### Endpoints de debug
- `/health` : Status de l'application
- `/model/info` : Informations sur le modèle
- Dans les logs : Temps de réponse, erreurs, métriques

### Performance

#### Optimisations recommandées

1. **Modèle**
   - Utiliser joblib pour la sérialisation
   - Cache du preprocessing
   - Validation des entrées côté client

2. **API**
   - Limiter les requêtes (rate limiting)
   - Compression GZIP
   - Cache des prédictions fréquentes

3. **Infrastructure**
   - Load balancer pour haute disponibilité
   - CDN pour les assets statiques
   - Base de données pour l'historique

## Ressources supplémentaires

### Documentation officielle
- [FastAPI](https://fastapi.tiangolo.com/)
- [Docker](https://docs.docker.com/)
- [AWS EC2](https://docs.aws.amazon.com/ec2/)
- [GCP Compute](https://cloud.google.com/compute/docs)
- [GitHub Actions](https://docs.github.com/en/actions)

### Bonnes pratiques MLOps
- [ML Engineering for Production](https://www.coursera.org/specializations/machine-learning-engineering-for-production-mlops)
- [MLOps Principles](https://ml-ops.org/)
- [Google Cloud MLOps](https://cloud.google.com/architecture/mlops-continuous-delivery-and-automation-pipelines-in-machine-learning)

---
