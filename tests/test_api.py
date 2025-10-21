#!/usr/bin/env python3

import requests
import sys
import subprocess
import time
import os


def start_api_server():
    try:
        os.chdir("src")

        process = subprocess.Popen(
            [
                "python",
                "-m",
                "uvicorn",
                "main:app",
                "--host",
                "0.0.0.0",
                "--port",
                "8000",
                "--reload",
            ]
        )

        time.sleep(3)
        return process
    except Exception as e:
        print(f"❌ Erreur lors du démarrage du serveur: {e}")
        return None


def test_health():
    print("Test du endpoint /health...")
    try:
        response = requests.get("http://localhost:8000/health")
        if response.status_code == 200:
            data = response.json()
            print("Health check OK")
            print(f"   Status: {data.get('status')}")
            print(f"   Model loaded: {data.get('model_loaded')}")
            return True
        else:
            print(f"❌ Health check failed: {response.status_code}")
            return False
    except Exception as e:
        print(f"❌ Erreur health check: {e}")
        return False


def test_model_info():
    print("\nTest du endpoint /model/info...")
    try:
        response = requests.get("http://localhost:8000/model/info")
        if response.status_code == 200:
            data = response.json()
            print("Model info OK")
            print(f"   Version: {data.get('model_version')}")
            print(f"   Training date: {data.get('training_date')}")
            print(f"   Training samples: {data.get('training_samples')}")
            print(f"   R² Score: {data.get('metrics', {}).get('r2_score', 'N/A'):.3f}")
            return True
        else:
            print(f"❌ Model info failed: {response.status_code}")
            if response.status_code == 503:
                print("   Le modèle n'est pas encore chargé")
            return False
    except Exception as e:
        print(f"❌ Erreur model info: {e}")
        return False


def test_prediction():
    print("\nTest du endpoint /predict...")

    test_data = {
        "surface": 85.0,
        "rooms": 4,
        "age": 10.0,
        "location_score": 7.5,
        "garage": True,
    }

    try:
        response = requests.post(
            "http://localhost:8000/predict",
            json=test_data,
            headers={"Content-Type": "application/json"},
        )

        if response.status_code == 200:
            data = response.json()
            print("Prédiction OK")
            print(f"   Prix prédit: {data.get('predicted_price'):,.0f}€")
            ci = data.get("confidence_interval", {})
            lower = ci.get("lower", 0)
            upper = ci.get("upper", 0)
            print(f"   Intervalle confiance: {lower:,.0f}€ - {upper:,.0f}€")
            return True
        else:
            print(f"❌ Prédiction failed: {response.status_code}")
            print(f"   Response: {response.text}")
            return False

    except Exception as e:
        print(f"❌ Erreur prédiction: {e}")
        return False


def test_batch_prediction():
    print("\nTest du endpoint /predict/batch...")

    test_batch = [
        {
            "surface": 85.0,
            "rooms": 4,
            "age": 10.0,
            "location_score": 7.5,
            "garage": True,
        },
        {
            "surface": 120.0,
            "rooms": 5,
            "age": 5.0,
            "location_score": 9.0,
            "garage": True,
        },
    ]

    try:
        response = requests.post(
            "http://localhost:8000/predict/batch",
            json=test_batch,
            headers={"Content-Type": "application/json"},
        )

        if response.status_code == 200:
            data = response.json()
            predictions = data.get("predictions", [])
            print(f"Prédiction batch OK ({len(predictions)} prédictions)")
            for i, pred in enumerate(predictions):
                print(f"   Bien {i + 1}: {pred.get('predicted_price'):,.0f}€")
            return True
        else:
            print(f"❌ Prédiction batch failed: {response.status_code}")
            print(f"   Response: {response.text}")
            return False

    except Exception as e:
        print(f"❌ Erreur prédiction batch: {e}")
        return False


def test_api_docs():
    print("\nTest de la documentation API")

    try:
        response = requests.get("http://localhost:8000/")
        if response.status_code == 200:
            print("Swagger UI accessible")
        else:
            print("❌ Swagger UI non accessible")

        response = requests.get("http://localhost:8000/openapi.json")
        if response.status_code == 200:
            schema = response.json()
            print("OpenAPI schema accessible")
            print(f"   Title: {schema.get('info', {}).get('title')}")
            return True
        else:
            print("❌ OpenAPI schema non accessible")
            return False

    except Exception as e:
        print(f"❌ Erreur documentation: {e}")
        return False


def test_invalid_data():
    print("\nTest avec données invalides...")

    invalid_data = {
        "surface": -10.0,
        "rooms": 0,
        "age": -5.0,
        "location_score": 15.0,
        "garage": True,
    }

    try:
        response = requests.post(
            "http://localhost:8000/predict",
            json=invalid_data,
            headers={"Content-Type": "application/json"},
        )

        if response.status_code == 422:
            print("Validation des données OK (erreur 422 attendue)")
            return True
        else:
            print(f"❌ Validation des données failed: {response.status_code}")
            print("   Expected 422 for invalid data")
            return False

    except Exception as e:
        print(f"❌ Erreur test données invalides: {e}")
        return False


def main():
    print("Démarrage des tests de l'API Housing Price Prediction\n")

    if not os.path.exists("models/housing_model.joblib"):
        print("❌ Modèle non trouvé! Veuillez d'abord exécuter train_model.py")
        sys.exit(1)

    print("Démarrage du serveur API...")
    server_process = None

    try:
        try:
            response = requests.get("http://localhost:8000/health", timeout=2)
            print("Serveur API déjà en cours d'exécution")
        except Exception:
            print("Démarrage du serveur API...")
            server_process = start_api_server()
            if not server_process:
                print("❌ Impossible de démarrer le serveur")
                sys.exit(1)

        print("Attente que l'API soit prête...")
        for i in range(10):
            try:
                response = requests.get("http://localhost:8000/health", timeout=2)
                if response.status_code == 200:
                    break
            except Exception:
                time.sleep(1)
        else:
            print("❌ L'API n'a pas démarré dans les temps")
            sys.exit(1)

        print("API prête!\n")

        tests = [
            test_health,
            test_model_info,
            test_prediction,
            test_batch_prediction,
            test_api_docs,
            test_invalid_data,
        ]

        results = []
        for test in tests:
            result = test()
            results.append(result)

        print("\nRésultats des tests:")
        print(f"Tests réussis: {sum(results)}/{len(results)}")
        print(f"❌ Tests échoués: {len(results) - sum(results)}/{len(results)}")

        if all(results):
            print("\nTous les tests ont réussi! L'API fonctionne correctement.")
            print("\nAccès à l'API:")
            print("   - API: http://localhost:8000")
            print("   - Documentation: http://localhost:8000/")
            print("   - ReDoc: http://localhost:8000/redoc")
        else:
            print("\nCertains tests ont échoué. Vérifiez les logs ci-dessus.")

    except KeyboardInterrupt:
        print("\nTests interrompus par l'utilisateur")

    finally:
        if server_process:
            print("\nArrêt du serveur...")
            server_process.terminate()
            server_process.wait()


if __name__ == "__main__":
    main()
