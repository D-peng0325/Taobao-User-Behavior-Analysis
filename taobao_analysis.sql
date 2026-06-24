-- 1. 创建电商分析专属数据库
CREATE DATABASE IF NOT EXISTS taobao_db;
USE taobao_db;

-- 2. 创建清洗后的用户行为数据表
CREATE TABLE IF NOT EXISTS user_behavior_cleaned (
    user_id INT NOT NULL,
    item_id INT NOT NULL,
    category_id INT NOT NULL,
    behavior_type VARCHAR(10) NOT NULL,
    `timestamp` DATETIME NOT NULL,
    `date` DATE NOT NULL,
    `hour` INT NOT NULL,

    -- 建立复合索引，优化后续的 SQL 聚合和 Tableau 查询速度
    INDEX idx_user_id (user_id),
    INDEX idx_behavior_date (behavior_type, `date`),
    INDEX idx_date_hour (`date`, `hour`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

SELECT COUNT(*) FROM user_behavior_cleaned;
SELECT * FROM user_behavior_cleaned LIMIT 10;

USE taobao_db;

-- 创建 ADS 层的漏斗分析视图
CREATE OR REPLACE VIEW view_user_funnel_daily AS
SELECT
    `date`,
    -- 1. 计算各项行为的总次数
    COUNT(CASE WHEN behavior_type = 'pv' THEN 1 END) AS total_pv,
    COUNT(CASE WHEN behavior_type = 'fav' THEN 1 END) AS total_fav,
    COUNT(CASE WHEN behavior_type = 'cart' THEN 1 END) AS total_cart,
    COUNT(CASE WHEN behavior_type = 'buy' THEN 1 END) AS total_buy,

    -- 2. 计算各项行为的独立去重人数 (UV)
    COUNT(DISTINCT CASE WHEN behavior_type = 'pv' THEN user_id END) AS uv_pv,
    COUNT(DISTINCT CASE WHEN behavior_type = 'fav' THEN user_id END) AS uv_fav,
    COUNT(DISTINCT CASE WHEN behavior_type = 'cart' THEN user_id END) AS uv_cart,
    COUNT(DISTINCT CASE WHEN behavior_type = 'buy' THEN user_id END) AS uv_buy
FROM user_behavior_cleaned
GROUP BY `date`;

-- 创建 DWS 层的 RFM 基础指标视图
CREATE OR REPLACE VIEW view_user_rfm_base AS
SELECT
    user_id,
    -- R: 截止到数据集最后一天(2017-12-03)，用户最近一次购买距今几天
    DATEDIFF('2017-12-03', MAX(CASE WHEN behavior_type = 'buy' THEN `date` END)) AS recency,

    -- F: 用户总共购买了多少次
    COUNT(CASE WHEN behavior_type = 'buy' THEN 1 END) AS frequency
FROM user_behavior_cleaned
GROUP BY user_id
-- 💡 优化：只有真正买过东西的用户，才参与 RFM 价值分层
HAVING frequency > 0;


CREATE OR REPLACE VIEW view_user_rfm_segmented AS
WITH rfm_with_global_avg AS (
    SELECT
        user_id,
        recency,
        frequency,
        AVG(recency) OVER() AS R_avg,
        AVG(frequency) OVER() AS F_avg
    FROM view_user_rfm_base
)
SELECT
    user_id,
    recency,
    frequency,
    CASE
        WHEN recency < R_avg AND frequency >= F_avg THEN '重要价值用户'
        WHEN recency < R_avg AND frequency < F_avg THEN '重要发展用户'
        WHEN recency >= R_avg AND frequency >= F_avg THEN '重要挽留用户'
        ELSE '一般保持用户'
    END AS customer_segment
FROM rfm_with_global_avg;

SELECT * FROM view_user_rfm_segmented;

USE taobao_db;

-- 创建 ADS 层：同期群用户留存视图
CREATE OR REPLACE VIEW view_user_retention_cohort AS
WITH user_first_date AS (
    -- Step 1: 找出每个用户的首次活跃日期（作为同期群的起点）
    SELECT user_id, MIN(`date`) AS first_active_date
    FROM user_behavior_cleaned
    GROUP BY user_id
),
user_activity_days AS (
    SELECT DISTINCT user_id, `date` AS active_date
    FROM user_behavior_cleaned
),
cohort_diff AS (
    SELECT
        f.first_active_date,
        a.active_date,
        DATEDIFF(a.active_date, f.first_active_date) AS diff_days,
        f.user_id
    FROM user_first_date f
    JOIN user_activity_days a ON f.user_id = a.user_id
)
SELECT
    first_active_date AS `首次活跃日期`,
    COUNT(DISTINCT CASE WHEN diff_days = 0 THEN user_id END) AS `初始人数`,
    COUNT(DISTINCT CASE WHEN diff_days = 1 THEN user_id END) AS `次日留存人数`,
    COUNT(DISTINCT CASE WHEN diff_days = 3 THEN user_id END) AS `3日留存人数`,
    COUNT(DISTINCT CASE WHEN diff_days = 5 THEN user_id END) AS `5日留存人数`
FROM cohort_diff
GROUP BY first_active_date
ORDER BY first_active_date;

SELECT * FROM view_user_funnel_daily;
SELECT * FROM view_user_retention_cohort;

-- 1、大盘基础活跃指标统计
SELECT
    COUNT(DISTINCT user_id) AS `独立用户数`,
    SUM(CASE WHEN behavior_type = 'buy' THEN 1 ELSE 0 END) AS `购买总数`,
    ROUND(SUM(CASE WHEN behavior_type = 'buy' THEN 1 ELSE 0 END) / COUNT(DISTINCT user_id) ,2) AS `平均去重`
FROM user_behavior_cleaned;

-- 2、用户分时行为洞察
SELECT
    hour AS `时间`,
    SUM(CASE WHEN behavior_type = 'cart' THEN 1 ELSE 0 END) AS `加购数`,
    SUM(CASE WHEN behavior_type = 'buy' THEN 1 ELSE 0 END) AS `购买总数`
FROM user_behavior_cleaned
GROUP BY hour
ORDER BY `购买总数` DESC;

-- 3、全站爆款商品 Top 10 榜单
SELECT
    item_id,
    category_id,
    COUNT(*) AS `总购买数`
FROM user_behavior_cleaned
WHERE behavior_type = 'buy'
GROUP BY item_id, category_id
ORDER BY `总购买数` DESC
LIMIT 10;

-- 4、忠诚用户挖掘
SELECT
    DISTINCT U1.user_id,
    U1.item_id,
    U1.date
FROM user_behavior_cleaned U1 INNER JOIN user_behavior_cleaned U2 ON U1.user_id = U2.user_id AND U1.behavior_type = 'buy' AND U2.behavior_type = 'fav' AND U1.date = U2.date AND U1.item_id = U2.item_id
