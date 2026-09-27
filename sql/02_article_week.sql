-- Step 2: Summarise 31.8M sales into one row per article per week.
-- Grain: article_id x week_start
--
-- Weeks start on Wednesday because the data ends on Tuesday 2020-09-22,
-- so the latest week is complete. The first week (starting 2018-09-19) is
-- partial (data starts Thursday) so it is dropped.

CREATE OR REPLACE TABLE `data-portfolio-509915.hm.article_week`
CLUSTER BY article_id AS

SELECT
  article_id,
  DATE_TRUNC(t_dat, WEEK(WEDNESDAY))            AS week_start,
  COUNT(*)                                      AS units,        -- 1 row = 1 unit
  SUM(price)                                    AS revenue,
  AVG(price)                                    AS avg_price,
  -- Median is used to detect markdowns: within one week an article sells at
  -- several prices (member offers, stores marking down at different times),
  -- and a few heavily discounted sales can drag the average down.
  APPROX_QUANTILES(price, 2)[OFFSET(1)]         AS median_price,
  ROUND(COUNTIF(sales_channel_id = 2) / COUNT(*), 3) AS online_share
FROM `data-portfolio-509915.hm.transactions`
WHERE DATE_TRUNC(t_dat, WEEK(WEDNESDAY)) > '2018-09-19'
GROUP BY article_id, week_start;
