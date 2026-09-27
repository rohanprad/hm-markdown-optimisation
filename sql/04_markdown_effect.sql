-- Step 4: Did the markdowns work?
--
-- For each markdown, compare weekly sales in the 4 weeks BEFORE vs the 4 weeks
-- FROM the markdown week onwards.
--
-- Raw lift on its own would credit the markdown for things that lift every
-- product (Black Friday, the start of summer). So we also measure how similar
-- products (same product type, still at full price) changed over the same
-- weeks, and divide by that:
--
--   adjusted lift = (marked-down item: after / before)
--                 / (full-price peers: after / before)
--
-- An adjusted lift of 2.0 means the markdown doubled sales compared with what
-- similar full-price products did over the same weeks.

CREATE OR REPLACE TABLE `data-portfolio-509915.hm.markdown_effect` AS

WITH md AS (
  SELECT m.*, a.product_type_name, a.product_group_name, a.index_group_name, a.garment_group_name
  FROM `data-portfolio-509915.hm.article_markdown` m
  JOIN `data-portfolio-509915.hm.articles` a USING (article_id)
),

-- Sales of each marked-down article, 4 weeks before vs 4 weeks after.
-- Weeks with no sales have no row, so we sum and divide by 4 (not AVG).
item AS (
  SELECT
    md.article_id,
    SUM(IF(w.week_start <  md.markdown_week, w.units, 0))   / 4 AS units_before_wk,
    SUM(IF(w.week_start >= md.markdown_week, w.units, 0))   / 4 AS units_after_wk,
    SUM(IF(w.week_start <  md.markdown_week, w.revenue, 0)) / 4 AS revenue_before_wk,
    SUM(IF(w.week_start >= md.markdown_week, w.revenue, 0)) / 4 AS revenue_after_wk
  FROM md
  JOIN `data-portfolio-509915.hm.article_week` w
    ON  w.article_id = md.article_id
    AND w.week_start BETWEEN DATE_SUB(md.markdown_week, INTERVAL 4 WEEK)
                         AND DATE_ADD(md.markdown_week, INTERVAL 3 WEEK)
  WHERE md.markdown_week IS NOT NULL
  GROUP BY md.article_id
),

-- Every (product type, markdown week) pair we need a peer comparison for
windows AS (
  SELECT DISTINCT product_type_name, markdown_week
  FROM md
  WHERE markdown_week IS NOT NULL
),

-- Peers: same product type, launched before the "before" window, and still at
-- full price until after the "after" window ends.
peer AS (
  SELECT
    win.product_type_name,
    win.markdown_week,
    SUM(IF(w.week_start <  win.markdown_week, w.units, 0)) AS peer_units_before,
    SUM(IF(w.week_start >= win.markdown_week, w.units, 0)) AS peer_units_after
  FROM windows win
  JOIN md p
    ON  p.product_type_name = win.product_type_name
    AND p.launch_week <= DATE_SUB(win.markdown_week, INTERVAL 4 WEEK)
    AND (p.markdown_week IS NULL OR p.markdown_week > DATE_ADD(win.markdown_week, INTERVAL 3 WEEK))
  JOIN `data-portfolio-509915.hm.article_week` w
    ON  w.article_id = p.article_id
    AND w.week_start BETWEEN DATE_SUB(win.markdown_week, INTERVAL 4 WEEK)
                         AND DATE_ADD(win.markdown_week, INTERVAL 3 WEEK)
  GROUP BY win.product_type_name, win.markdown_week
)

SELECT
  md.article_id,
  md.product_type_name,
  md.product_group_name,
  md.index_group_name,
  md.garment_group_name,
  md.launch_week,
  md.markdown_week,
  md.weeks_to_markdown,
  md.markdown_depth,
  md.depth_band,
  i.units_before_wk,
  i.units_after_wk,
  SAFE_DIVIDE(i.units_after_wk, i.units_before_wk)                 AS raw_unit_lift,
  SAFE_DIVIDE(p.peer_units_after, p.peer_units_before)             AS peer_unit_change,
  SAFE_DIVIDE(SAFE_DIVIDE(i.units_after_wk, i.units_before_wk),
              SAFE_DIVIDE(p.peer_units_after, p.peer_units_before)) AS adjusted_unit_lift,
  -- Revenue: peers stay at full price, so their revenue moves with their units
  SAFE_DIVIDE(SAFE_DIVIDE(i.revenue_after_wk, i.revenue_before_wk),
              SAFE_DIVIDE(p.peer_units_after, p.peer_units_before)) AS adjusted_revenue_change,
  p.peer_units_before
FROM md
JOIN item i USING (article_id)
LEFT JOIN peer p
  ON p.product_type_name = md.product_type_name AND p.markdown_week = md.markdown_week
-- Need a meaningful base: 5+ units in the 4 weeks before (so a jump from
-- 0.25 to 2 units/week doesn't look like an 8x lift), and a real peer group.
WHERE i.units_before_wk * 4 >= 5
  AND p.peer_units_before >= 50;
