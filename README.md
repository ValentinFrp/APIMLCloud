# Housing Price Prediction API

Une API de prédiction de prix immobilier basée sur machine learning, déployable sur le cloud avec CI/CD automatisé.

## Objectif du projet

Ce projet fait partie d'une formation MLOps et démontre :
- Développement d'un modèle ML simple et efficace
- Création d'une API REST robuste avec FastAPI
- Containerisation avec Docker
- Pipeline CI/CD avec GitHub Actions
- Déploiement cloud (AWS/GCP)
- Tests automatisés et monitoring

## Démarrage rapide

### Prérequis
- Python 3.9+
- pip
- Docker (optionnel)

### Installation locale

1. **Clone du repository**
   ```bash
   git clone <git@github.com:ValentinFrp/APIMLCloud.git>
   cd APIMLCloud
   ```

2. **Installation des dépendances**
   ```bash
   pip install -r requirements.txt
   ```

3. **Entraînement du modèle**
   ```bash
   cd src
   python train_model.py
   ```

4. **Lancement de l'API**
   ```bash
   python main.py
   ```

5. **Accès à l'API**
   - API: http://localhost:8000
   - Documentation Swagger: http://localhost:8000/
   - ReDoc: http://localhost:8000/redoc

## Architecture du projet

```
APIMLCloud/
├── src/
│   ├── main.py              # API FastAPI principale
│   └── train_model.py       # Script d'entraînement du modèle
├── models/                  # Modèles ML sauvegardés
│   └── housing_model.joblib
├── data/                    # Données d'entraînement
│   └── housing_data.csv
├── tests/                   # Tests unitaires
│   └── test_api.py
├── .github/
│   └── workflows/           # Pipelines CI/CD
├── Dockerfile              # Configuration Docker
├── requirements.txt        # Dépendances Python
└── README.md              # Documentation
```

## Le modèle ML

### Caractéristiques d'entrée
- **surface** (float): Surface du bien en m² [20-500]
- **rooms** (int): Nombre de pièces [1-15]
- **age** (float): Âge du bien en années [0-100]
- **location_score** (float): Score de localisation [1-10]
- **garage** (bool): Présence d'un garage

### Algorithme
- **Random Forest Regressor** avec 100 estimateurs
- Normalisation StandardScaler
- Métriques: R², MAE, RMSE

### Performance
- R² Score: ~0.95 sur données synthétiques
- MAE: ~25,000€
- RMSE: ~35,000€

## Endpoints de l'API

### `GET /health`
Point de santé de l'API
```json
{
  "status": "healthy",
  "timestamp": "2024-01-15T10:30:00",
  "model_loaded": true
}
```

### `GET /model/info`
Informations sur le modèle
```json
{
  "model_version": "1.0.0",
  "training_date": "2024-01-15T10:00:00",
  "training_samples": 1600,
  "features": ["surface", "rooms", "age", "location_score", "garage"],
  "metrics": {
    "r2_score": 0.952,
    "mae": 24567.89,
    "rmse": 34123.45
  }
}
```

### `POST /predict`
Prédiction pour un bien unique
```json
// Request
{
  "surface": 85.0,
  "rooms": 4,
  "age": 10.0,
  "location_score": 7.5,
  "garage": true
}

// Response
{
  "predicted_price": 285420.50,
  "confidence_interval": {
    "lower": 251297.05,
    "upper": 319543.95
  },
  "model_version": "1.0.0",
  "prediction_timestamp": "2024-01-15T10:30:00"
}
```

### `POST /predict/batch`
Prédiction en lot (max 100 biens)
```json
// Request
[
  {
    "surface": 85.0,
    "rooms": 4,
    "age": 10.0,
    "location_score": 7.5,
    "garage": true
  },
]

// Response
{
  "predictions": [
    {
      "predicted_price": 285420.50,
      "confidence_interval": {...},
      "model_version": "1.0.0",
      "prediction_timestamp": "2024-01-15T10:30:00"
    }
  ]
}
```

## Tests

### Lancer les tests
```bash
cd tests
python -m pytest test_api.py -v
```

### Coverage des tests
- Endpoints de santé
- Validation des données d'entrée
- Prédictions unitaires et en lot
- Gestion d'erreurs
- Documentation API

## Docker

### Build de l'image
```bash
docker build -t housing-price-api .
```

### Lancement du container
```bash
docker run -p 8000:8000 housing-price-api
```

## Déploiement

### Variables d'environnement
```bash
export ENV=production
export HOST=0.0.0.0
export PORT=8000
export LOG_LEVEL=info
```

### CI/CD avec GitHub Actions
Le pipeline automatique :
1. Tests unitaires
2. Linting et formatage
3. Build Docker
4. Déploiement sur cloud

## Monitoring et Observabilité

### Métriques disponibles
- Nombre de prédictions par heure
- Temps de réponse moyen
- Taux d'erreur
- Santé du modèle

### Logs structurés
```json
{
  "timestamp": "2024-01-15T10:30:00",
  "level": "INFO",
  "message": "Prédiction effectuée: 285,420€",
  "prediction_id": "uuid-123",
  "model_version": "1.0.0"
}
```

## 🛠️ Stack technique

### Backend
- **FastAPI**: Framework web moderne et rapide
- **Pydantic**: Validation des données
- **scikit-learn**: Machine learning
- **Pandas/Numpy**: Manipulation de données

### DevOps
- **Docker**: Containerisation
- **GitHub Actions**: CI/CD
- **pytest**: Tests automatisés
- **uvicorn**: Serveur ASGI

### Cloud (à venir)
- **AWS EC2 / GCP Compute Engine**: Infrastructure
- **AWS RDS / GCP Cloud SQL**: Base de données
- **AWS CloudWatch / GCP Monitoring**: Monitoring

## Apprentissages MLOps

Ce projet couvre les compétences MLOps essentielles :

### Phase 1 - Consolidation (ACTUEL)
- [x] Modèle ML fonctionnel
- [x] API REST robuste
- [x] Tests automatisés
- [x] Documentation complète

### Phase 2 - Pipeline avancé (EN COURS)
- [ ] CI/CD GitHub Actions
- [ ] Dockerisation
- [ ] Déploiement cloud

### Phase 3 - Production (À VENIR)
- [ ] Monitoring avancé
- [ ] Scaling automatique
- [ ] A/B testing des modèles
- [ ] Feedback loop

## Contribution

1. Fork le project
2. Créer une branche feature (`git checkout -b feature/AmazingFeature`)
3. Commit les changements (`git commit -m 'Add some AmazingFeature'`)
4. Push vers la branche (`git push origin feature/AmazingFeature`)
5. Ouvrir une Pull Request

## TODO

### Court terme
- [ ] Finaliser les tests unitaires
- [ ] Ajouter la configuration Docker
- [ ] Configurer GitHub Actions
- [ ] Déployer sur AWS/GCP

### Moyen terme
- [ ] Ajouter une base de données
- [ ] Implémenter le monitoring
- [ ] Ajouter des métriques métier
- [ ] Interface web simple

### Long terme
- [ ] Réentraînement automatique
- [ ] Pipeline de données
- [ ] Modèles multiples (A/B testing)
- [ ] Feedback utilisateur

## License

Ce projet est sous licence MIT - voir le fichier [LICENSE](LICENSE) pour plus de détails.

## 👤 Auteur

**Ton Nom**
- GitHub: [@ValentinFrp](https://github.com/ValentinFrp)
- LinkedIn: [Valentin Frappart](https://www.linkedin.com/in/valentin-frappart-a73b252b4/)

---

⭐ **N'hésite pas à star le repo si ce projet t'a aidé dans ton apprentissage MLOps !**
