/******************************************************************************
 * [의도] 공간 데이터 통합 및 시공간 집계 (Spatial Join & Time-series Aggregation)
 * 1. 결합 키 부재 해결: 대여소와 유동인구 데이터 간 공통 컬럼이 없으므로, 위경도 좌표를 
 * 활용해 대여소를 특정 행정동(ADM_NM) 폴리곤 내에 매핑함.
 * 2. 분석 단위 확장: 개별 대여소 중심 분석에서 지역적 특성 파악이 용이한 '행정동' 단위로 
 * 데이터를 집계하여 유동인구/날씨 데이터와 결합 기반 마련.
 ******************************************************************************/

-- 1단계: 대여소 좌표 기반 행정동 매핑 (Spatial Mapping)
CREATE OR REPLACE TABLE station_district_mapping AS
SELECT 
    s.대여소_ID,
    b.ADM_NM AS 행정동,
    b.SIGUNGU_NM AS 자치구
FROM station_info s
JOIN administrative_boundaries b 
  ON ST_CONTAINS(b.geometry, ST_GEOMFROMTEXT(CONCAT('POINT(', s.경도, ' ', s.위도, ')'), 4326))
/* [의도] 점(대여소)이 면(행정동 경계) 안에 포함되는지를 판별하는 Spatial Join 수행 */
;

-- 2단계: 시공간 마스터 스켈레톤 및 대여/반납 데이터 통합 집계
WITH RECURSIVE TimeSeries AS (
    -- 데이터의 연속성 확보를 위해 2023년 모든 시간대 생성
    SELECT '2023-01-01 00:00:00' AS dt
    UNION ALL
    SELECT DATE_ADD(dt, INTERVAL 1 HOUR) FROM TimeSeries WHERE dt < '2023-12-31 23:00:00'
),
MasterSkeleton AS (
    -- 시간(Time)과 공간(District)의 모든 조합을 생성하여 대여 기록이 없는 0인 지점까지 포함
    SELECT MONTH(dt) AS mon, DAY(dt) AS day, HOUR(dt) AS hr, d.행정동
    FROM TimeSeries
    CROSS JOIN (SELECT DISTINCT 행정동 FROM station_district_mapping) d
),
RentAggregated AS (
    -- 대여 이력 전처리 및 집계 
    SELECT 
        MONTH(r.대여일시) AS mon, DAY(r.대여일시) AS day, HOUR(r.대여일시) AS hr,
        m_start.행정동 AS 대여행정동,
        COUNT(r.자전거번호) AS 총대여수,
        -- 파생 변수: 이동 반경 및 패턴 분석 지표
        AVG(CASE WHEN r.대여대여소번호 = r.반납대여소번호 THEN 1 ELSE 0 END) AS 대여소일치비율,
        AVG(CASE WHEN m_start.행정동 = m_end.행정동 THEN 1 ELSE 0 END) AS 행정동일치비율,
        -- 이용자 프로필 집계
        AVG(CASE WHEN r.성별 = 'M' THEN 1 ELSE 0 END) AS 성비,
        AVG(YEAR(CURDATE()) - r.생년) AS 평균연령,
        AVG(r.이용시간_분) AS 평균이용시간,
        AVG(r.이용거리_M) AS 평균이용거리
    FROM bike_rental_history r
    -- 공간 정보 결합: 대여/반납소 번호를 기준으로 행정동 정보 매핑
    LEFT JOIN station_district_mapping m_start ON r.대여대여소번호 = m_start.대여소_ID
    LEFT JOIN station_district_mapping m_end ON r.반납대여소번호 = m_end.대여소_ID
    WHERE r.이용거리_M != 0 AND r.이용시간_분 != 0 -- 무효 데이터 필터링
    GROUP BY 1, 2, 3, 4
)
-- 3단계: 최종 통합 데이터 마트 구축 (날씨/유동인구 결합 기반 완성)
SELECT 
    ms.mon, ms.day, ms.hr, ms.행정동,
    COALESCE(ra.총대여수, 0) AS 총대여수,
    COALESCE(ra.행정동일치비율, 0) AS 행정동일치비율,
    COALESCE(ra.성비, 0.5) AS 성비,
    COALESCE(ra.평균연령, 0) AS 평균연령,
    COALESCE(ra.평균이용시간, 0) AS 평균이용시간
FROM MasterSkeleton ms
LEFT JOIN RentAggregated ra 
    ON ms.mon = ra.mon AND ms.day = ra.day AND ms.hr = ra.hr AND ms.행정동 = ra.대여행정동
/* [의도] 시공간 스켈레톤을 기준으로 Left Join하여 데이터 누락 없이 0의 이용량까지 
   예측 모델에 반영 가능하도록 정규화함 */
;
