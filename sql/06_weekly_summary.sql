-- Step 6: Small weekly table for the dashboard's trend chart.
-- Grain: week x department x price status
-- Shows how much of each week's sales came from marked-down products,
-- which makes H&M's sale seasons (January, summer) visible.

CREATE OR REPLACE TABLE `data-portfolio-509915.hm.weekly_summary` AS

SELECT
  w.week_start,
  a.index_group_name,
  CASE
    WHEN m.article_id IS NULL                  THEN 'Launched before data'
    WHEN w.week_start >= m.markdown_week       THEN 'Marked down'
    ELSE 'Full price'
  END                AS price_status,
  SUM(w.units)       AS units,
  SUM(w.revenue)     AS revenue
FROM `data-portfolio-509915.hm.article_week` w
JOIN `data-portfolio-509915.hm.articles` a USING (article_id)
LEFT JOIN `data-portfolio-509915.hm.article_markdown` m USING (article_id)
GROUP BY 1, 2, 3;
