import pandas as pd
import numpy as np
from sklearn.model_selection import train_test_split
from sklearn.ensemble import RandomForestRegressor
from sklearn.preprocessing import StandardScaler
from sklearn.metrics import mean_absolute_error, mean_squared_error, r2_score
import joblib
import os
from datetime import datetime


def generate_synthetic_data(n_samples=1000):
    np.random.seed(42)

    surface = np.random.normal(100, 30, n_samples)
    surface = np.clip(surface, 20, 300)

    rooms = np.random.poisson(4, n_samples)
    rooms = np.clip(rooms, 1, 10)

    age = np.random.exponential(20, n_samples)
    age = np.clip(age, 0, 100)

    location_score = np.random.uniform(1, 10, n_samples)

    garage = np.random.binomial(1, 0.6, n_samples)

    price_per_sqm = np.random.uniform(2000, 5000, n_samples)

    price = (
        surface
        * price_per_sqm
        * (1 + location_score / 20)
        * (1 - age / 200)
        * (1 + garage * 0.1)
    )

    noise = np.random.normal(0, price * 0.1, n_samples)
    price = price + noise
    price = np.clip(price, 50000, 2000000)

    df = pd.DataFrame(
        {
            "surface": surface,
            "rooms": rooms,
            "age": age,
            "location_score": location_score,
            "garage": garage,
            "price": price,
        }
    )

    return df


def train_model():
    print("Génération des données d'entraînement...")
    df = generate_synthetic_data(2000)

    os.makedirs("../data", exist_ok=True)
    df.to_csv("../data/housing_data.csv", index=False)
    print(f"Données sauvegardées: {len(df)} échantillons")

    X = df[["surface", "rooms", "age", "location_score", "garage"]]
    y = df["price"]

    X_train, X_test, y_train, y_test = train_test_split(
        X, y, test_size=0.2, random_state=42
    )

    print("Préprocessing des données...")
    scaler = StandardScaler()
    X_train_scaled = scaler.fit_transform(X_train)
    X_test_scaled = scaler.transform(X_test)

    print("Entraînement du modèle...")
    model = RandomForestRegressor(
        n_estimators=100, max_depth=10, random_state=42, n_jobs=-1
    )

    model.fit(X_train_scaled, y_train)

    y_pred = model.predict(X_test_scaled)

    mae = mean_absolute_error(y_test, y_pred)
    mse = mean_squared_error(y_test, y_pred)
    r2 = r2_score(y_test, y_pred)
    rmse = np.sqrt(mse)

    print("\nMétriques du modèle:")
    print(f"- R² Score: {r2:.3f}")
    print(f"- MAE: {mae:,.0f}€")
    print(f"- RMSE: {rmse:,.0f}€")
    print(f"- MSE: {mse:,.0f}")

    feature_importance = pd.DataFrame(
        {"feature": X.columns, "importance": model.feature_importances_}
    ).sort_values("importance", ascending=False)

    print("\nImportance des features:")
    for _, row in feature_importance.iterrows():
        print(f"- {row['feature']}: {row['importance']:.3f}")

    os.makedirs("../models", exist_ok=True)

    model_info = {
        "model": model,
        "scaler": scaler,
        "features": list(X.columns),
        "metrics": {"r2_score": r2, "mae": mae, "rmse": rmse, "mse": mse},
        "feature_importance": feature_importance.to_dict("records"),
        "training_date": datetime.now().isoformat(),
        "training_samples": len(X_train),
    }

    joblib.dump(model_info, "../models/housing_model.joblib")
    print("Modèle sauvegardé dans '../models/housing_model.joblib'")

    return model_info


if __name__ == "__main__":
    print("Démarrage de l'entraînement du modèle de prédiction immobilière")
    model_info = train_model()
    print("\nEntraînement terminé avec succès!")
