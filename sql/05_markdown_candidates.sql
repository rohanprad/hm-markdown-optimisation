-- Step 5: Which products should be marked down now?
--
-- "Now" = the latest 4 weeks in the data (weeks starting 2020-08-26 to 2020-09-16).
--
-- A product is a markdown candidate when it is:
--   1. still selling (sold in the last 4 weeks)
--   2. still at full price (never marked down, and last-4-week price within 10% of full price)
--   3. old enough to judge (on sale for 8+ weeks)
--   4. slow: selling at less than half the rate of sale of similar products
--      (same product type in the same department, also full price, 8+ weeks old).
--      Department matters: baby trousers can't be judged against ladies' trousers.
--
-- The suggested depth comes from Step 4: for each department, the depth band
-- that grew revenue the most in past markdowns.

CREATE OR REPLACE TABLE `data-portfolio-509915.hm.markdown_candidates` AS

WITH params AS (
  SELECT DATE '2020-08-26' AS window_start,   -- first of the latest 4 weeks
         DATE '2020-07-29' AS prior_start     -- first of the 4 weeks before that
),

recent AS (
  SELECT
    w.article_id,
    SUM(IF(w.week_start >= p.window_start, w.units, 0)) / 4 AS ros_now,        -- units/week
    SUM(IF(w.week_start <  p.window_start, w.units, 0)) / 4 AS ros_prior,
    SAFE_DIVIDE(SUM(IF(w.week_start >= p.window_start, w.median_price * w.units, 0)),
                SUM(IF(w.week_start >= p.window_start, w.units, 0)))        AS price_now,
    SUM(IF(w.week_start >= p.window_start, w.revenue, 0)) / 4               AS revenue_now_wk
  FROM `data-portfolio-509915.hm.article_week` w
  CROSS JOIN params p
  WHERE w.week_start >= p.prior_start
  GROUP BY w.article_id
),

-- Full-price, still-selling, 8+ weeks old
eligible AS (
  SELECT
    r.*,
    m.launch_week,
    DATE_DIFF(DATE '2020-09-16', m.launch_week, WEEK) AS weeks_on_sale,
    r.price_now / m.full_price                         AS price_vs_full,
    a.prod_name, a.product_type_name, a.product_group_name,
    a.index_group_name, a.department_name, a.colour_group_name
  FROM recent r
  JOIN `data-portfolio-509915.hm.article_markdown` m USING (article_id)
  JOIN `data-portfolio-509915.hm.articles` a USING (article_id)
  WHERE r.ros_now > 0
    AND m.markdown_week IS NULL
    AND r.price_now / m.full_price >= 0.90
    AND m.launch_week <= DATE '2020-07-22'   -- 8+ weeks on sale
),

-- Benchmark: typical rate of sale for each product type within a department
benchmark AS (
  SELECT
    index_group_name,
    product_type_name,
    APPROX_QUANTILES(ros_now, 100)[OFFSET(50)] AS peer_median_ros,
    COUNT(*)                                   AS peer_count
  FROM eligible
  GROUP BY index_group_name, product_type_name
  HAVING COUNT(*) >= 10     -- need enough peers for a fair comparison
),

-- Best depth band per department, learnt from past markdowns (Step 4)
best_depth AS (
  SELECT index_group_name, depth_band AS recommended_depth,
         median_rev_change AS expected_revenue_change,
         median_unit_lift  AS expected_unit_lift
  FROM (
    SELECT index_group_name, depth_band,
      APPROX_QUANTILES(adjusted_revenue_change, 100)[OFFSET(50)] AS median_rev_change,
      APPROX_QUANTILES(adjusted_unit_lift, 100)[OFFSET(50)]      AS median_unit_lift
    FROM `data-portfolio-509915.hm.markdown_effect`
    GROUP BY 1, 2
  )
  QUALIFY ROW_NUMBER() OVER (PARTITION BY index_group_name ORDER BY median_rev_change DESC) = 1
)

SELECT
  e.article_id,
  e.prod_name,
  e.product_type_name,
  e.product_group_name,
  e.index_group_name,
  e.department_name,
  e.colour_group_name,
  e.launch_week,
  e.weeks_on_sale,
  ROUND(e.price_vs_full, 3)                          AS price_vs_full,
  e.ros_now,
  e.ros_prior,
  CAST(e.ros_now * 4 AS INT64)                       AS units_last_4wk,  -- easier to read than 0.3/week
  ROUND(SAFE_DIVIDE(e.ros_now, e.ros_prior) - 1, 3)  AS ros_trend,       -- vs previous 4 weeks
  -- Display version: no sales in the prior 4 weeks means there is nothing to compare with
  CASE
    WHEN e.ros_prior = 0 THEN '–'
    WHEN ROUND((SAFE_DIVIDE(e.ros_now, e.ros_prior) - 1) * 100) = 0 THEN '0%'   -- not "+0%"
    ELSE FORMAT('%+.0f%%', (SAFE_DIVIDE(e.ros_now, e.ros_prior) - 1) * 100)
  END                                                AS trend_label,
  b.peer_median_ros,
  b.peer_count,
  ROUND(e.ros_now / b.peer_median_ros, 3)            AS ros_vs_peers,    -- 1.0 = typical
  e.ros_now / b.peer_median_ros < 0.5                AS is_candidate,
  d.recommended_depth,
  ROUND(d.expected_unit_lift, 2)                     AS expected_unit_lift,
  ROUND(d.expected_revenue_change, 2)                AS expected_revenue_change,
  e.revenue_now_wk
FROM eligible e
JOIN benchmark b USING (index_group_name, product_type_name)
LEFT JOIN best_depth d USING (index_group_name);
