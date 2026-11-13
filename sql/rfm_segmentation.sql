-- ============================================================================
-- CUSTOMER SEGMENTATION & RFM FEATURE ENGINEERING (SQL)
-- Compatible with PostgreSQL / MySQL 8.0+ / BigQuery
-- ============================================================================

-- 1. Create Base Transactions Table
CREATE TABLE IF NOT EXISTS retail_transactions (
    order_id VARCHAR(20) PRIMARY KEY,
    customer_id VARCHAR(20) NOT NULL,
    city VARCHAR(50),
    order_date DATE NOT NULL,
    category VARCHAR(50),
    payment_mode VARCHAR(30),
    order_amount_inr DECIMAL(12, 2),
    discount_pct INT
);

-- 2. Compute Raw RFM Metrics & Purchasing Behaviour per Customer
WITH snapshot AS (
    SELECT DATE '2026-11-01' AS analysis_date
),
customer_rfm AS (
    SELECT
        t.customer_id,
        t.city,
        DATEDIFF(s.analysis_date, MAX(t.order_date)) AS recency_days,
        COUNT(DISTINCT t.order_id) AS frequency_orders,
        ROUND(SUM(t.order_amount_inr), 2) AS monetary_inr,
        ROUND(AVG(t.order_amount_inr), 2) AS avg_order_value_inr,
        ROUND(AVG(t.discount_pct), 1) AS avg_discount_pct
    FROM retail_transactions t
    CROSS JOIN snapshot s
    GROUP BY t.customer_id, t.city
),

-- 3. Assign RFM Quintile Scores (1 to 5) using NTILE Window Functions
rfm_scores AS (
    SELECT
        *,
        NTILE(5) OVER (ORDER BY recency_days DESC) AS r_score,      -- Lower recency = Higher score (5)
        NTILE(5) OVER (ORDER BY frequency_orders ASC) AS f_score,   -- Higher frequency = Higher score (5)
        NTILE(5) OVER (ORDER BY monetary_inr ASC) AS m_score        -- Higher spend = Higher score (5)
    FROM customer_rfm
),

-- 4. Rule-Based SQL Behavioural Segmentation
rfm_segmented AS (
    SELECT
        *,
        CONCAT(r_score, f_score, m_score) AS rfm_cell,
        CASE
            WHEN r_score >= 4 AND f_score >= 4 AND m_score >= 4 THEN 'VIP Champions'
            WHEN r_score >= 3 AND f_score >= 3 AND m_score >= 3 THEN 'Loyal Spenders'
            WHEN r_score >= 4 AND f_score <= 2 THEN 'Recent / Potential Loyalists'
            WHEN r_score <= 2 AND f_score >= 3 AND m_score >= 3 THEN 'At-Risk High Value'
            ELSE 'Dormant / Low-Value'
        END AS sql_segment
    FROM rfm_scores
)

-- 5. Executive Segment Summary Report
SELECT
    sql_segment,
    COUNT(customer_id) AS customer_count,
    ROUND(COUNT(customer_id) * 100.0 / SUM(COUNT(customer_id)) OVER (), 1) AS customer_share_pct,
    ROUND(AVG(recency_days), 1) AS avg_recency_days,
    ROUND(AVG(frequency_orders), 1) AS avg_frequency,
    ROUND(AVG(monetary_inr), 2) AS avg_lifetime_spend_inr,
    ROUND(SUM(monetary_inr), 2) AS total_segment_revenue_inr,
    ROUND(SUM(monetary_inr) * 100.0 / SUM(SUM(monetary_inr)) OVER (), 1) AS revenue_share_pct
FROM rfm_segmented
GROUP BY sql_segment
ORDER BY total_segment_revenue_inr DESC;

-- 6. Category & Payment Mode Affinity by Segment (Post-Clustering Join)
SELECT
    s.segment,
    t.category,
    t.payment_mode,
    COUNT(DISTINCT t.order_id) AS total_orders,
    ROUND(SUM(t.order_amount_inr), 2) AS total_spend_inr
FROM retail_transactions t
JOIN segmented_customers s ON t.customer_id = s.customer_id
GROUP BY s.segment, t.category, t.payment_mode
ORDER BY s.segment, total_spend_inr DESC;
