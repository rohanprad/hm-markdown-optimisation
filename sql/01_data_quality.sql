-- Step 1: Can the data be trusted?
-- One row per check, so the output reads like a reconciliation report.

WITH t AS (
  SELECT * FROM `data-portfolio-509915.hm.transactions`
),
a AS (
  SELECT * FROM `data-portfolio-509915.hm.articles`
),
-- The export has no quantity column: buying 2 of the same item on the same
-- day appears as 2 identical rows. So repeats are expected, not errors.
repeats AS (
  SELECT COUNT(*) - COUNT(DISTINCT FORMAT('%t', t)) AS repeated_rows FROM t
)

SELECT 'transactions: rows' AS check_name, CAST(COUNT(*) AS STRING) AS result FROM t
UNION ALL SELECT 'transactions: first date', CAST(MIN(t_dat) AS STRING) FROM t
UNION ALL SELECT 'transactions: last date', CAST(MAX(t_dat) AS STRING) FROM t
UNION ALL SELECT 'transactions: days with no sales',
  CAST(DATE_DIFF(MAX(t_dat), MIN(t_dat), DAY) + 1 - COUNT(DISTINCT t_dat) AS STRING) FROM t
UNION ALL SELECT 'transactions: null values (any column)',
  CAST(COUNTIF(t_dat IS NULL OR customer_id IS NULL OR article_id IS NULL
               OR price IS NULL OR sales_channel_id IS NULL) AS STRING) FROM t
UNION ALL SELECT 'transactions: price <= 0', CAST(COUNTIF(price <= 0) AS STRING) FROM t
UNION ALL SELECT 'transactions: sales channels',
  STRING_AGG(DISTINCT CAST(sales_channel_id AS STRING) ORDER BY CAST(sales_channel_id AS STRING)) FROM t
UNION ALL SELECT 'transactions: repeated identical rows (= extra units)',
  CAST(repeated_rows AS STRING) FROM repeats
UNION ALL SELECT 'transactions: rows with unknown article_id',
  CAST(COUNTIF(a.article_id IS NULL) AS STRING)
  FROM t LEFT JOIN a USING (article_id)
UNION ALL SELECT 'articles: rows', CAST(COUNT(*) AS STRING) FROM a
UNION ALL SELECT 'articles: duplicate article_id',
  CAST(COUNT(*) - COUNT(DISTINCT article_id) AS STRING) FROM a
UNION ALL SELECT 'articles: never sold',
  CAST(COUNTIF(article_id NOT IN (SELECT DISTINCT article_id FROM t)) AS STRING) FROM a
