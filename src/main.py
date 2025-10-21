from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, Field
import joblib
import numpy as np
import os
from typing import Dict
import logging
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = FastAPI(
    title="Housing Price Prediction API",
    description="API de prédiction de prix immobilier basée sur les caractéristiques",
    version="1.0.0",
    docs_url="/",
    redoc_url="/redoc",
)

model_info = None


class HousingFeatures(BaseModel):
    surface: float = Field(..., ge=20, le=500, description="Surface du bien en m²")
    rooms: int = Field(..., ge=1, le=15, description="Nombre de pièces")
    age: float = Field(..., ge=0, le=100, description="Âge du bien en années")
    location_score: float = Field(
        ..., ge=1, le=10, description="Score de localisation (1=mauvais, 10=excellent)"
    )
    garage: bool = Field(..., description="Présence d'un garage")

    class Config:
        schema_extra = {
            "example": {
                "surface": 85.0,
                "rooms": 4,
                "age": 10.0,
                "location_score": 7.5,
                "garage": True,
            }
        }


class PredictionResponse(BaseModel):
    predicted_price: float = Field(..., description="Prix prédit en euros")
    confidence_interval: Dict[str, float] = Field(
        ..., description="Intervalle de confiance"
    )
    model_version: str = Field(..., description="Version du modèle utilisé")
    prediction_timestamp: str = Field(..., description="Timestamp de la prédiction")


class ModelInfo(BaseModel):
    model_version: str
    training_date: str
    training_samples: int
    features: list
    metrics: Dict[str, float]
    feature_importance: list


def load_model():
    global model_info

    model_path = "../models/housing_model.joblib"

    if not os.path.exists(model_path):
        logger.error(f"Modèle non trouvé: {model_path}")
        raise FileNotFoundError(f"Le fichier de modèle {model_path} n'existe pas")

    try:
        model_info = joblib.load(model_path)
        logger.info("Modèle chargé avec succès")
        return True
    except Exception as e:
        logger.error(f"❌ Erreur lors du chargement du modèle: {e}")
        raise e


@app.on_event("startup")
async def startup_event():
    """
    Événement de démarrage - charge le modèle
    """
    logger.info("Démarrage de l'API Housing Price Prediction")
    try:
        load_model()
        logger.info(f"Modèle prêt - R² Score: {model_info['metrics']['r2_score']:.3f}")
    except Exception as e:
        logger.error(f"❌ Impossible de charger le modèle: {e}")


@app.get("/health")
async def health_check():
    return {
        "status": "healthy",
        "timestamp": datetime.now().isoformat(),
        "model_loaded": model_info is not None,
    }


@app.get("/model/info", response_model=ModelInfo)
async def get_model_info():
    if model_info is None:
        raise HTTPException(status_code=503, detail="Modèle non chargé")

    return ModelInfo(
        model_version="1.0.0",
        training_date=model_info["training_date"],
        training_samples=model_info["training_samples"],
        features=model_info["features"],
        metrics=model_info["metrics"],
        feature_importance=model_info["feature_importance"],
    )


@app.post("/predict", response_model=PredictionResponse)
async def predict_price(features: HousingFeatures):
    if model_info is None:
        raise HTTPException(status_code=503, detail="Modèle non chargé")

    try:
        garage_numeric = 1 if features.garage else 0

        feature_array = np.array(
            [
                [
                    features.surface,
                    features.rooms,
                    features.age,
                    features.location_score,
                    garage_numeric,
                ]
            ]
        )

        feature_array_scaled = model_info["scaler"].transform(feature_array)

        predicted_price = model_info["model"].predict(feature_array_scaled)[0]

        rmse = model_info["metrics"]["rmse"]
        confidence_lower = max(0, predicted_price - rmse)
        confidence_upper = predicted_price + rmse

        logger.info(f"Prédiction effectuée: {predicted_price:,.0f}€")

        return PredictionResponse(
            predicted_price=float(predicted_price),
            confidence_interval={
                "lower": float(confidence_lower),
                "upper": float(confidence_upper),
            },
            model_version="1.0.0",
            prediction_timestamp=datetime.now().isoformat(),
        )

    except Exception as e:
        logger.error(f"❌ Erreur lors de la prédiction: {e}")
        raise HTTPException(status_code=500, detail=f"Erreur de prédiction: {str(e)}")


@app.post("/predict/batch")
async def predict_batch(features_list: list[HousingFeatures]):
    if model_info is None:
        raise HTTPException(status_code=503, detail="Modèle non chargé")

    if len(features_list) > 100:
        raise HTTPException(status_code=400, detail="Maximum 100 prédictions par batch")

    try:
        predictions = []

        for features in features_list:
            garage_numeric = 1 if features.garage else 0

            feature_array = np.array(
                [
                    [
                        features.surface,
                        features.rooms,
                        features.age,
                        features.location_score,
                        garage_numeric,
                    ]
                ]
            )

            feature_array_scaled = model_info["scaler"].transform(feature_array)
            predicted_price = model_info["model"].predict(feature_array_scaled)[0]

            rmse = model_info["metrics"]["rmse"]
            confidence_lower = max(0, predicted_price - rmse)
            confidence_upper = predicted_price + rmse

            predictions.append(
                PredictionResponse(
                    predicted_price=float(predicted_price),
                    confidence_interval={
                        "lower": float(confidence_lower),
                        "upper": float(confidence_upper),
                    },
                    model_version="1.0.0",
                    prediction_timestamp=datetime.now().isoformat(),
                )
            )

        logger.info(f"Batch de {len(predictions)} prédictions effectué")
        return {"predictions": predictions}

    except Exception as e:
        logger.error(f"❌ Erreur lors de la prédiction batch: {e}")
        raise HTTPException(
            status_code=500, detail=f"Erreur de prédiction batch: {str(e)}"
        )


if __name__ == "__main__":
    import uvicorn

    try:
        load_model()
        print("Modèle chargé")
    except Exception as e:
        print(f"❌ Erreur chargement modèle: {e}")

    uvicorn.run("main:app", host="0.0.0.0", port=8000, reload=True, log_level="info")
