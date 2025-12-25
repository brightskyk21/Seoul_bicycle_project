import xgboost as xgb
import shap
import numpy as np
import pandas as pd
from sklearn.preprocessing import StandardScaler
from sklearn.metrics import mean_squared_error, r2_score
import matplotlib.pyplot as plt

# -----------------------------------------------------------------------------
# [의도] 데이터 세분화 및 정규화 (Data Preparation)
# 1. 시계열 검증: 2023년 데이터를 Train, 2024년 데이터를 Test로 분리하여 미래 수요 예측력 검증
# 2. 범주형 변수 제거: '자치구', '행정동' 등 고유 명칭을 제외하고 수치 피처 위주로 학습하여 모델의 범용성 확보
# -----------------------------------------------------------------------------

drop_columns = ['자치구', '행정동']

X_train = rent_df_23.drop(drop_columns + ['날짜', '총대여수'], axis=1)
y_train = rent_df_23['총대여수']
X_test = rent_df_24.drop(drop_columns + ['날짜', '총대여수'], axis=1)
y_test = rent_df_24['총대여수']

# 피처 간 스케일 차이로 인한 편향을 방지하기 위해 표준화(Standardization) 수행
scaler = StandardScaler()
X_train_scaled = scaler.fit_transform(X_train)
X_test_scaled = scaler.transform(X_test)

X_train_scaled = pd.DataFrame(X_train_scaled, columns=X_train.columns)
X_test_scaled = pd.DataFrame(X_test_scaled, columns=X_test.columns)

# -----------------------------------------------------------------------------
# [의도] 최적화된 XGBoost 모델 학습
# - 하이퍼파라미터 최적화: Optuna를 활용하여 50회 이상의 Trial을 통해 최적의 조합 도출 
# - 정규화(L1, L2): reg_alpha, reg_lambda를 적용하여 과적합 방지 및 일반화 성능 극대화
# -----------------------------------------------------------------------------

params = {
    'max_depth': 13,
    'learning_rate': 0.05196177016351211,
    'n_estimators': 375,
    'min_child_weight': 4,
    'subsample': 0.772411828364268,
    'colsample_bytree': 0.5409873046287774,
    'gamma': 3.4989359755217726,
    'reg_alpha': 0.022277510182597746,
    'reg_lambda': 7.9277382772545515,
    'random_state': 42,
    'tree_method': 'hist',
    'device': 'cuda', # GPU 가속을 통한 연산 효율 증대 [cite: 638]
    'objective': 'reg:squarederror'
}

final_model = xgb.XGBRegressor(**params)
final_model.fit(X_train_scaled, y_train)

# 모델 평가 수행 [cite: 644-647]
y_pred = final_model.predict(X_test_scaled)
rmse = np.sqrt(mean_squared_error(y_test, y_pred))
r2 = r2_score(y_test, y_pred)

print(f"\nTest RMSE: {rmse:.2f}")
print(f"Test R2 Score: {r2:.2f}")

# -----------------------------------------------------------------------------
# [의도] XAI(Explainable AI)를 통한 비즈니스 인사이트 도출
# - 블랙박스인 ML 모델의 예측 근거를 시각화하여 '재배치 전략'의 정책적 타당성 확보 [cite: 685-686, 726]
# -----------------------------------------------------------------------------

explainer = shap.TreeExplainer(final_model)
shap_values = explainer.shap_values(X_test_scaled)

# Summary Plot: 전체 피처가 예측값에 미치는 영향력 분포 파악 [cite: 652]
plt.figure(figsize=(12, 8))
shap.summary_plot(shap_values, X_test_scaled)

# [분석 인사이트] 행정동/자치구 내 일치 비율이 높을수록 대여량이 증가함 -> 단거리 순환 수요의 중요성 입증 [cite: 727, 770, 776]
feature_importance = pd.DataFrame({
    'feature': X_train.columns,
    'importance': np.abs(shap_values).mean(0)
})

# Dependence Plot: 피처 간 상호작용 및 비선형적 관계 분석 [cite: 673-677]
top_features = feature_importance.sort_values('importance', ascending=False).head(7)['feature'].values
for feature in top_features:
    shap.dependence_plot(feature, shap_values, X_test_scaled)

# Waterfall Plot: 예측 오차가 가장 큰 케이스를 개별 분석하여 모델의 한계 및 개선 방향 식별 [cite: 678-684]
errors = np.abs(y_test - y_pred)
max_error_idx = errors.idxmax()
row_number = X_test_scaled.index.get_loc(max_error_idx)
shap.waterfall_plot(shap.Explanation(values=shap_values[row_number],
                                     base_values=explainer.expected_value,
                                     data=X_test_scaled.loc[max_error_idx],
                                     feature_names=X_test_scaled.columns))
