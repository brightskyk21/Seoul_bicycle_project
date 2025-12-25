/******************************************************************************
 * [의도] 보고서 내 EDA 핵심 지표의 정량적 산출 및 검증
 * 데이터 분석가로서 시각화의 근거가 되는 수치를 SQL로 직접 추출하여 분석의 
 * 신뢰성을 확보하고, 대용량 데이터 환경에서의 집계 능력을 증명함.
 ******************************************************************************/

-- 가. 23년 행정동별 일평균 이용량 및 유동인구 수
-- [의도] 이용량이 집중된 지역(가양1동, 여의동 등)과 실제 거주/생활 인구 밀집 지역의 차이 파악
SELECT 
    행정동,
    AVG(총대여수) AS 일평균_이용량,
    AVG(총생활인구수) AS 일평균_유동인구
FROM integrated_bike_data_23
GROUP BY 행정동
ORDER BY 일평균_이용량 DESC;


-- 나. 23년 대여소 당 이용량 (대여 효율성 분석)
-- [의도] 대여소 한 곳당 발생하는 부하를 측정하여 하천 근처 등 특정 지역의 높은 효율성 확인 
SELECT 
    행정동,
    COUNT(DISTINCT 대여소_ID) AS 대여소수,
    SUM(총대여수) AS 총이용량,
    SUM(총대여수) / COUNT(DISTINCT 대여소_ID) AS 대여소당_이용량
FROM integrated_bike_data_23
GROUP BY 행정동
ORDER BY 대여소당_이용량 DESC;


-- 다. 23년-24년 이용 증감율 및 대여소 증가량
-- [의도] 수색동 등 이용량이 급증한 지역과 가양1동/여의동 등 인프라가 확충된 지역의 추이 비교 
SELECT 
    a.행정동,
    (SUM(b.총대여수) - SUM(a.총대여수)) / SUM(a.총대여수) * 100 AS 이용_증감율_pct,
    (COUNT(DISTINCT b.대여소_ID) - COUNT(DISTINCT a.대여소_ID)) AS 대여소_증가량
FROM integrated_bike_data_23 a
JOIN integrated_bike_data_24 b ON a.행정동 = b.행정동
GROUP BY a.행정동;


-- 라. 23년 대여소 수 현황 (공급 적정성 진단)
-- [의도] '일 평균 대여소당 대여 36회'를 기준으로 과잉/부족 지역을 분류하여 재배치 근거 마련
WITH StationEfficiency AS (
    SELECT 
        행정동,
        COUNT(DISTINCT 대여소_ID) AS 현재_대여소수,
        SUM(총대여수) / 365 AS 일평균_총대여수
    FROM integrated_bike_data_23
    GROUP BY 행정동
)
SELECT 
    행정동,
    현재_대여소수,
    ROUND(일평균_총대여수 / 36) AS 적정_대여소수,
    CASE 
        WHEN 현재_대여소수 > ROUND(일평균_총대여수 / 36) + 2 THEN '공급 과잉'
        WHEN 현재_대여소수 < ROUND(일평균_총대여수 / 36) - 2 THEN '공급 부족'
        ELSE '공급 적정'
    END AS 공급_현황
FROM StationEfficiency;


-- 마. 유동인구-대여 전환율 분석
-- [의도] 유동인구가 대여로 이어지는 비율(평균 0.047%)을 산출하여 인프라 접근성 개선 필요성 도출
SELECT 
    행정동,
    SUM(총대여수) AS 총대여수,
    SUM(총생활인구수) AS 총유동인구,
    (SUM(총대여수) / SUM(총생활인구수)) * 100 AS 전환율_pct
FROM integrated_bike_data_23
GROUP BY 행정동
ORDER BY 전환율_pct DESC;
