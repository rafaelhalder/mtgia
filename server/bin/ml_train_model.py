#!/usr/bin/env python3
"""
MTG Deck Quality Predictor — ML Training Script
=================================================

Treina um modelo preditivo de qualidade de deck usando features
extraídas pelo pipeline Dart (bin/ml_extract_features.dart).

Dependências:
    pip install pandas scikit-learn xgboost matplotlib

Uso:
    # 1. Extrair features (Dart)
    cd server && dart run bin/ml_extract_features.dart

    # 2. Treinar modelo (Python)
    python3 server/bin/ml_train_model.py
    python3 server/bin/ml_train_model.py --input=custom_data.csv --target=sim_consistency_score

O modelo treinado pode ser usado para:
- Prever a qualidade de um deck ANTES de simular (rápido)
- Ranquear decks em torneios
- Sugerir melhorias (features com maior importância)
"""

import argparse
import os
import sys

try:
    import pandas as pd
    import numpy as np
    from sklearn.model_selection import train_test_split, cross_val_score
    from sklearn.ensemble import RandomForestRegressor, GradientBoostingRegressor
    from sklearn.preprocessing import LabelEncoder
    from sklearn.metrics import mean_squared_error, r2_score, mean_absolute_error
except ImportError as e:
    print(f"❌ Dependência faltando: {e}")
    print("   Instale com: pip install pandas scikit-learn numpy")
    sys.exit(1)

try:
    import xgboost as xgb
    HAS_XGBOOST = True
except ImportError:
    HAS_XGBOOST = False


def load_and_prepare(csv_path: str, target_col: str):
    """Carrega CSV e prepara features numéricas."""
    df = pd.read_csv(csv_path)
    print(f"📊 Dataset: {len(df)} registros, {len(df.columns)} colunas")
    print(f"   Colunas: {list(df.columns)}")

    # Remove colunas não-features
    drop_cols = ['deck_id', 'deck_name']
    df = df.drop(columns=[c for c in drop_cols if c in df.columns])

    # Verifica se o target existe
    if target_col not in df.columns:
        print(f"❌ Coluna target '{target_col}' não encontrada.")
        print(f"   Disponíveis: {list(df.columns)}")
        sys.exit(1)

    # Remove registros sem target
    df = df.dropna(subset=[target_col])
    if len(df) == 0:
        print("❌ Nenhum registro com target válido.")
        sys.exit(1)

    # Encode colunas categóricas
    label_encoders = {}
    for col in df.select_dtypes(include=['object']).columns:
        le = LabelEncoder()
        df[col] = le.fit_transform(df[col].astype(str))
        label_encoders[col] = le

    # Separa features e target
    X = df.drop(columns=[target_col])
    y = df[target_col]

    return X, y, label_encoders


def train_and_evaluate(X, y, model_name: str):
    """Treina e avalia o modelo."""
    X_train, X_test, y_train, y_test = train_test_split(
        X, y, test_size=0.2, random_state=42
    )

    print(f"\n{'='*60}")
    print(f"🤖 Modelo: {model_name}")
    print(f"   Train: {len(X_train)} | Test: {len(X_test)}")

    # Seleciona modelo
    if model_name == 'xgboost' and HAS_XGBOOST:
        model = xgb.XGBRegressor(
            n_estimators=200,
            max_depth=6,
            learning_rate=0.1,
            subsample=0.8,
            colsample_bytree=0.8,
            random_state=42,
            verbosity=0,
        )
    elif model_name == 'gradient_boosting':
        model = GradientBoostingRegressor(
            n_estimators=200,
            max_depth=5,
            learning_rate=0.1,
            subsample=0.8,
            random_state=42,
        )
    else:
        model = RandomForestRegressor(
            n_estimators=200,
            max_depth=10,
            min_samples_split=5,
            random_state=42,
            n_jobs=-1,
        )

    # Cross-validation
    cv_scores = cross_val_score(model, X_train, y_train, cv=5,
                                scoring='neg_mean_squared_error')
    cv_rmse = np.sqrt(-cv_scores.mean())
    print(f"   CV RMSE: {cv_rmse:.4f} (±{np.sqrt(-cv_scores).std():.4f})")

    # Treina no conjunto completo de treino
    model.fit(X_train, y_train)

    # Avalia no teste
    y_pred = model.predict(X_test)
    rmse = np.sqrt(mean_squared_error(y_test, y_pred))
    mae = mean_absolute_error(y_test, y_pred)
    r2 = r2_score(y_test, y_pred)

    print(f"\n   📈 Resultados no teste:")
    print(f"      RMSE: {rmse:.4f}")
    print(f"      MAE:  {mae:.4f}")
    print(f"      R²:   {r2:.4f}")

    # Feature importance
    if hasattr(model, 'feature_importances_'):
        importances = pd.Series(
            model.feature_importances_, index=X.columns
        ).sort_values(ascending=False)

        print(f"\n   🏆 Top 10 Features mais importantes:")
        for feat, imp in importances.head(10).items():
            bar = '█' * int(imp * 50)
            print(f"      {feat:30s} {imp:.4f} {bar}")

    return model, rmse, r2


def main():
    parser = argparse.ArgumentParser(
        description='MTG Deck Quality ML Trainer'
    )
    parser.add_argument(
        '--input', default='ml_training_data.csv',
        help='Caminho do CSV de features (default: ml_training_data.csv)'
    )
    parser.add_argument(
        '--target', default='sim_consistency_score',
        help='Coluna target para predição (default: sim_consistency_score)'
    )
    parser.add_argument(
        '--model', default='all',
        choices=['random_forest', 'gradient_boosting', 'xgboost', 'all'],
        help='Modelo para treinar (default: all)'
    )
    args = parser.parse_args()

    # Verifica se o arquivo existe
    if not os.path.exists(args.input):
        print(f"❌ Arquivo não encontrado: {args.input}")
        print("   Execute primeiro: dart run bin/ml_extract_features.dart")
        sys.exit(1)

    print("╔══════════════════════════════════════════════╗")
    print("║   MTG ML Training Pipeline v1.0              ║")
    print("╚══════════════════════════════════════════════╝")

    X, y, encoders = load_and_prepare(args.input, args.target)

    print(f"\n🎯 Target: {args.target}")
    print(f"   Min: {y.min():.2f} | Max: {y.max():.2f} | "
          f"Mean: {y.mean():.2f} | Std: {y.std():.2f}")

    if len(X) < 10:
        print(f"\n⚠️ Dataset muito pequeno ({len(X)} registros).")
        print("   Resultados podem não ser confiáveis.")
        print("   Execute mais simulações para gerar dados.")

    models_to_train = []
    if args.model == 'all':
        models_to_train = ['random_forest', 'gradient_boosting']
        if HAS_XGBOOST:
            models_to_train.append('xgboost')
    else:
        models_to_train = [args.model]

    best_model = None
    best_rmse = float('inf')
    best_name = ''

    for model_name in models_to_train:
        model, rmse, r2 = train_and_evaluate(X, y, model_name)
        if rmse < best_rmse:
            best_rmse = rmse
            best_model = model
            best_name = model_name

    print(f"\n{'='*60}")
    print(f"🏆 Melhor modelo: {best_name} (RMSE: {best_rmse:.4f})")

    # Tenta gerar gráfico de importância
    try:
        import matplotlib
        matplotlib.use('Agg')
        import matplotlib.pyplot as plt

        if hasattr(best_model, 'feature_importances_'):
            importances = pd.Series(
                best_model.feature_importances_, index=X.columns
            ).sort_values(ascending=False).head(15)

            fig, ax = plt.subplots(figsize=(10, 6))
            importances.plot(kind='barh', ax=ax, color='#8B5CF6')
            ax.set_title(f'Top 15 Feature Importances ({best_name})')
            ax.set_xlabel('Importance')
            ax.invert_yaxis()
            plt.tight_layout()

            output_img = args.input.replace('.csv', '_importances.png')
            plt.savefig(output_img, dpi=150)
            print(f"\n📊 Gráfico salvo: {output_img}")
    except ImportError:
        print("\n💡 Instale matplotlib para gerar gráficos: pip install matplotlib")

    print("\n🏁 Pipeline de treino concluído!")


if __name__ == '__main__':
    main()
