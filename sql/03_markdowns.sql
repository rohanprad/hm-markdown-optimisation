-- Step 3: Find each article's full price and its first markdown.
--
-- Full price  = the article's price in its first 4 weeks on sale (launch price).
-- Markdown    = the first week the median price is 15%+ below full price
--               AND it stays 15%+ below for the next 2 weeks too (3 weeks in a
--               row), so short promotions and one-off dips are not counted.
--               (A 2-week rule was tested first: 44% of its shallow "markdowns"
--               went back to full price, i.e. they were promotions.)
--
-- Only articles launched after the data starts are included: anything already
-- on sale in the first 8 weeks might have been marked down before we can see it.

CREATE OR REPLACE TABLE `data-portfolio-509915.hm.article_markdown` AS

WITH weeks AS (
  SELECT
    *,
    MIN(week_start) OVER (PARTITION BY article_id) AS launch_week
  FROM `data-portfolio-509915.hm.article_week`
),

full_price AS (
  SELECT
    article_id,
    launch_week,
    SUM(median_price * units) / SUM(units) AS full_price   -- unit-weighted
  FROM weeks
  WHERE week_start < DATE_ADD(launch_week, INTERVAL 4 WEEK)
  GROUP BY article_id, launch_week
  HAVING launch_week >= '2018-11-21'   -- launched 8+ weeks after data starts
),

flagged AS (
  SELECT
    w.article_id,
    w.week_start,
    w.median_price / f.full_price AS price_ratio,
    LEAD(w.median_price / f.full_price) OVER (PARTITION BY w.article_id ORDER BY w.week_start) AS next_week_ratio,
    LEAD(w.median_price / f.full_price, 2) OVER (PARTITION BY w.article_id ORDER BY w.week_start) AS week_after_next_ratio,
    LEAD(w.week_start, 2)               OVER (PARTITION BY w.article_id ORDER BY w.week_start) AS week_after_next_start
  FROM weeks w
  JOIN full_price f USING (article_id)
  WHERE w.week_start >= DATE_ADD(f.launch_week, INTERVAL 4 WEEK)  -- after launch period
),

first_markdown AS (
  SELECT
    article_id,
    MIN(week_start) AS markdown_week
  FROM flagged
  WHERE price_ratio <= 0.85
    AND next_week_ratio <= 0.85
    AND week_after_next_ratio <= 0.85
    AND week_after_next_start = DATE_ADD(week_start, INTERVAL 2 WEEK)  -- 3 consecutive weeks
  GROUP BY article_id
)

SELECT
  f.article_id,
  f.launch_week,
  f.full_price,
  m.markdown_week,
  DATE_DIFF(m.markdown_week, f.launch_week, WEEK)   AS weeks_to_markdown,
  ROUND(1 - fl.price_ratio, 3)                      AS markdown_depth,
  CASE
    WHEN m.markdown_week IS NULL  THEN 'No markdown'
    WHEN 1 - fl.price_ratio < 0.30 THEN '15-30%'
    WHEN 1 - fl.price_ratio < 0.50 THEN '30-50%'
    ELSE '50%+'
  END AS depth_band
FROM full_price f
LEFT JOIN first_markdown m USING (article_id)
LEFT JOIN flagged fl
  ON fl.article_id = m.article_id AND fl.week_start = m.markdown_week;
