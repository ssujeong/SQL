/* 13장. 시계열에 따른 사용자의 개별적인 행동 분석
- 사용자의 액션의 '시간(타이밍)'에 주목하여 분석해보자 
- 사용자가 최종 결과(성과)에 도달할 때까지 어느 정도의 기간(과정)이 필요한지를 알면, 의사 결정이나 대책 수립 시 도움이 됨
- 사용자의 성장 과정, 행동 패턴, ... => 어떤 부분을 개선해야하는 지 명확히 파악 가능 */

/* 13-1. 사용자의 '액션 간격(리드 타임)' 집계 
- 데이터 패턴에 따라 리드 타임 계산하는 3가지 방법 ============================================================ */

-- 1. 같은 레코드에 있는 두 개의 날짜로 계산할 경우 (날짜끼리 빼면됨)
-- (ex. 숙박 시설, 음식점 등은 신청일, 숙박일, 방문일을 한꺼번에 저장함)
-- 신청일과 숙박일의 리드 타임 계산
WITH reservations(reservation_id, register_date, visit_date, days) AS (
	VALUES
	(1, date '2016-09-01', date '2016-10-01', 3),
	(2, date '2016-09-20', date '2016-10-01', 2),
	(3, date '2016-09-30', date '2016-11-20', 2),
	(4, date '2016-10-01', date '2017-01-03', 2),
	(5, date '2016-11-01', date '2016-12-28', 3)
)
SELECT reservation_id,
	register_date,
	visit_date,
	visit_date::date - register_date::date AS lead_time
FROM reservations
;
	
-- 2. 여러 테이블에 있는 여러 개의 날짜로 계산할 경우 (JOIN 후, 날짜끼리 빼기)
-- (ex. 자료 청구, 예측, 계약 등 여러 단계가 존재하는 경우. 각각의 데이터가 다른 테이블에 저장되는 경우가 많음)
-- 각 단계별 리드 타임과 토탈 리드 타임 계산
WITH
requests(user_id, product_id, request_date) AS (
	VALUES
	('U001', '1', date '2016-09-01'),
	('U001', '2', date '2016-09-20'),
	('U002', '3', date '2016-09-30'),
	('U003', '4', date '2016-10-01'),
	('U004', '5', date '2016-11-01')
),
estimates(user_id, product_id, estimate_date) AS (
	VALUES
	('U001', '2', date '2016-09-21'),
	('U002', '3', date '2016-10-15'),
	('U003', '4', date '2016-10-15'),
	('U004', '5', date '2016-12-01')
),
orders(user_id, product_id, order_date) AS (
	VALUES
	('U001', '2', date '2016-10-01'),
	('U004', '5', date '2016-12-05')
)
SELECT r.user_id,
	r.product_id,
	-- leadtime
	e.estimate_date::date - r.request_date::date AS estimate_lead_time,
	o.order_date::date - e.estimate_date::date AS order_lead_time,
	o.order_date::date - r.request_date::date AS total_lead_time
FROM requests r LEFT OUTER JOIN estimates e ON r.user_id = e.user_id AND r.product_id = e.product_id
				LEFT OUTER JOIN orders o ON r.user_id = o.user_id AND r.product_id = o.product_id
;


-- 3. 같은 테이블의 다른 레코드에 있는 날짜로 계산할 경우 (LAG 함수 사용)
-- (ex. e-commerce 사이트에서 이전 구매일로부터 다음 구매일까지의 간격을 알고 싶은 경우)
-- 이전 구매일로부터의 일수를 계산
WITH
purchase_log(user_id, product_id, purchase_date) AS (
	VALUES
	('U001', '1', '2016-09-01'),
	('U001', '2', '2016-09-20'),
	('U002', '3', '2016-09-30'),
	('U001', '4', '2016-10-01'),
	('U002', '5', '2016-11-01')
)
SELECT user_id,
	purchase_date,
	purchase_date::date - LAG(purchase_date::date) OVER(PARTITION BY user_id ORDER BY purchase_date) AS leaf_time
FROM purchase_log
;

/* 13-2. 카트 추가 후, 구매했는지 파악 
- 카트에 넣은 상품을 구매하지 않고 이탈한 상활을 '카트 탈락'이라고 부름 ==================================================*/

-- 1. 카트에 추가된지 48시간 이내에 구매되지 않은 상품을 '카트 탈락'이라 정의하고, 카트 탈락률 집계
-- 1-1. 상품들이 카트에 추가된 시각과 구매된 시각을 산출
WITH
row_action_log AS (
	SELECT dt,
		user_id,
		action,
		-- 쉼표로 구문된 products list 전개 하기 (regexp_split_to_table 함수 사용)
		regexp_split_to_table(products, ',') AS product_id,
		stamp
	FROM action_log		
),
action_time_status AS (
	-- 사용자&상품 조합의 카트 추가 시간, 구매 시간 추출
	SELECT user_id,
		product_id,
		MIN(CASE WHEN action = 'add_cart' THEN dt END) AS dt,
		-- 각 액션 시간 추출
		MIN(CASE WHEN action = 'add_cart' THEN stamp END) AS add_cart_time,
		MIN(CASE WHEN action = 'purchase' THEN stamp END) AS purchase_time,
		-- 차이 구하기 (timestamp자료형으로 변환해서 간격 구한 뒤, EXTRACT(epoch ~)로 초단위 변환)
		EXTRACT(epoch from
			   	MIN(CASE WHEN action = 'purchase' THEN stamp::timestamp END)
				- MIN(CASE WHEN action = 'add_cart' THEN stamp::timestamp END)
			   ) AS lead_time
	FROM row_action_log
	GROUP BY user_id, product_id
)
SELECT user_id,
	product_id,
	add_cart_time,
	purchase_time,
	lead_time
FROM action_time_status
ORDER BY user_id, product_id
;

-- 1-2. 카트 추가 후, n시간 이내에 구매된 상품 수와 구매율 집계
WITH
row_action_log AS (
	SELECT dt,
		user_id,
		action,
		-- 쉼표로 구문된 products list 전개 하기 (regexp_split_to_table 함수 사용)
		regexp_split_to_table(products, ',') AS product_id,
		stamp
	FROM action_log		
),
action_time_status AS (
	-- 사용자&상품 조합의 카트 추가 시간, 구매 시간 추출
	SELECT user_id,
		product_id,
		MIN(CASE WHEN action = 'add_cart' THEN dt END) AS dt,
		-- 각 액션 시간 추출
		MIN(CASE WHEN action = 'add_cart' THEN stamp END) AS add_cart_time,
		MIN(CASE WHEN action = 'purchase' THEN stamp END) AS purchase_time,
		-- 차이 구하기 (timestamp자료형으로 변환해서 간격 구한 뒤, EXTRACT(epoch ~)로 초단위 변환)
		EXTRACT(epoch from
			   	MIN(CASE WHEN action = 'purchase' THEN stamp::timestamp END)
				- MIN(CASE WHEN action = 'add_cart' THEN stamp::timestamp END)
			   ) AS lead_time
	FROM row_action_log
	GROUP BY user_id, product_id
),
purchase_lead_time_flag AS (
	SELECT user_id,
		product_id,
		dt,
		CASE WHEN lead_time <= 1 * 60 * 60 THEN 1 ELSE 0 END AS purchase_1_hour,
		CASE WHEN lead_time <= 6 * 60 * 60 THEN 1 ELSE 0 END AS purchase_6_hour,
		CASE WHEN lead_time <= 24 * 60 * 60 THEN 1 ELSE 0 END AS purchase_24_hour,
		CASE WHEN lead_time <= 48 * 60 * 60 THEN 1 ELSE 0 END AS purchase_48_hour,
		CASE WHEN lead_time IS NULL 
					OR NOT (lead_time <= 48 * 60 * 60) THEN 1 ELSE 0 END AS not_purchase
	FROM action_time_status
)
SELECT dt,
	COUNT(*) AS add_cart,
	SUM(purchase_1_hour) AS purchase_1_hour,
	AVG(purchase_1_hour) AS purchase_1_hour_rate,
	SUM(purchase_6_hour) AS purchase_6_hour,
	AVG(purchase_6_hour) AS purchase_6_hour_rate,
	SUM(purchase_24_hour) AS purchase_24_hour,
	AVG(purchase_24_hour) AS purchase_24_hour_rate,
	SUM(purchase_48_hour) AS purchase_48_hour,
	AVG(purchase_48_hour) AS purchase_48_hour_rate,
	SUM(not_purchase) AS not_purchase,
	AVG(not_purchase) AS not_purchase_rate
FROM purchase_lead_time_flag
GROUP BY dt
;


/* 13-3. 등록으로부터 시간 경과에 따른 매출 집계 */

-- 1. 사용자 등록을 월별로 집계하고, n일 경과 시점의 1인당 매출 금액을 집계
-- 1-1. 사용자들의 등록일부터 경과한 일수별 매출을 계산
WITH
index_intervals(index_name, interval_begin_date, interval_end_date) AS (
	VALUES
	('30 day sales amount', 0, 30),
	('45 day sales amount', 0, 45),
	('60 day sales amount', 0, 60)
),
mst_users_with_base_date AS (
	SELECT user_id,
		-- 기준일: 등록일
		register_date AS base_date
	FROM mst_users
),
purchase_log_with_index_date AS (
	SELECT u.user_id,
		u.base_date,
		-- 액션 날짜, 로그 전체의 최신 날짜 -> date 자료형으로 변환
		CAST(a.stamp AS date) AS action_date,
		MAX(CAST(a.stamp AS date)) OVER() AS latest_date,
		substring(a.stamp, 1, 7) AS year_month,
		i.index_name,
		-- 지표 대상 기간의 시작일과 종료일 계산
		CAST(u.base_date::date + '1 day'::interval * i.interval_begin_date AS date) AS index_begin_date,
		CAST(u.base_date::date + '1 day'::interval * i.interval_end_date AS date) AS index_end_date,
		a.amount
	FROM mst_users_with_base_date u LEFT OUTER JOIN action_log a 
										ON u.user_id = a.user_id AND a.action = 'purchase'
									CROSS JOIN index_intervals i
)
SELECT *
FROM purchase_log_with_index_date
;

-- 1-2. 월별 등록자수와 경과일수별 매출 집계
WITH
index_intervals(index_name, interval_begin_date, interval_end_date) AS (
	VALUES
	('30 day sales amount', 0, 30),
	('45 day sales amount', 0, 45),
	('60 day sales amount', 0, 60)
),
mst_users_with_base_date AS (
	SELECT user_id,
		-- 기준일: 등록일
		register_date AS base_date
	FROM mst_users
),
purchase_log_with_index_date AS (
	SELECT u.user_id,
		u.base_date,
		-- 액션 날짜, 로그 전체의 최신 날짜 -> date 자료형으로 변환
		CAST(a.stamp AS date) AS action_date,
		MAX(CAST(a.stamp AS date)) OVER() AS latest_date,
		substring(a.stamp, 1, 7) AS year_month,
		i.index_name,
		-- 지표 대상 기간의 시작일과 종료일 계산
		CAST(u.base_date::date + '1 day'::interval * i.interval_begin_date AS date) AS index_begin_date,
		CAST(u.base_date::date + '1 day'::interval * i.interval_end_date AS date) AS index_end_date,
		a.amount
	FROM mst_users_with_base_date u LEFT OUTER JOIN action_log a 
										ON u.user_id = a.user_id AND a.action = 'purchase'
									CROSS JOIN index_intervals i
),
user_purchase_amount AS (
	SELECT user_id,
		year_month,
		index_name,
		-- 3. 지표 대상 기산에 구매한 금액을 사용자별로 합계 내기
		SUM(
			-- 1. 지표의 대상 기간의 종료일이 로그의 최신 날짜에 포함되었는지 확인
			CASE WHEN index_end_date <= latest_date THEN
				-- 2. 지표의 대상 기간에 구매한 경우에는 구매 금액, 이외의 경우 0 지정
				CASE 
					WHEN action_date BETWEEN index_begin_date AND index_end_date THEN amount ELSE 0
				END
			END
		) AS index_date_amount
	FROM purchase_log_with_index_date
	GROUP BY user_id, year_month, index_name, index_begin_date, index_end_date
)
SELECT year_month,
	-- 등록자수
	COUNT(user_id) AS users,
	index_name,
	-- 지표의 대상 기간 동안 구매한 사용자 수
	COUNT(CASE WHEN index_date_amount > 0 THEN user_id END) AS purchase_users,
	-- 지표의 대상 기간 동안의 매출 합계
	SUM(index_date_amount) AS total_amount,
	-- 등록자별 평균 매출 = 등록자 1명당 매출 평균
	AVG(index_date_amount) AS avg_amount
FROM user_purchase_amount
GROUP BY 1,3
ORDER BY 1,3
;