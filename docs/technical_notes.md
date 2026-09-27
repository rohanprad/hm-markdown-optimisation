# Technical notes

Detail behind the [README](../README.md): data, method, decisions and caveats.

## Data

[H&M Personalized Fashion Recommendations](https://www.kaggle.com/competitions/h-and-m-personalized-fashion-recommendations)
(Kaggle), loaded into BigQuery.

| Table | Rows | Used for |
|---|---|---|
| `transactions` | 31,788,324 | Every item sold: date, product, price, channel |
| `articles` | 105,542 | Product details: type, department, colour |

**Limitations**
- **Prices are anonymised** by H&M (scaled), so results are shown as % changes,
  not £. Relative price changes, and so markdown depths, are unaffected.
- **No stock data.** True sell-through can't be calculated, so slow sellers are
  identified by **rate of sale vs similar products**, which is how many
  merchandisers flag markdown candidates in practice.
- **No markdown flag.** Markdowns are detected from price history (Step 3).

## Pipeline

All transformation is in BigQuery SQL. Each step builds a table the next one uses.

| Step | File | What it does |
|---|---|---|
| 0 | [load_to_bigquery.py](../load/load_to_bigquery.py) | One-off load of the Kaggle export into BigQuery, clustered by date and product |
| 1 | [01_data_quality.sql](../sql/01_data_quality.sql) | Reconciliation checks: row counts, date coverage, nulls, orphan products |
| 2 | [02_article_week.sql](../sql/02_article_week.sql) | 31.8M sales → 2.2M product-week rows (units, revenue, median price) |
| 3 | [03_markdowns.sql](../sql/03_markdowns.sql) | Full price = launch price; markdown = first week price is 15%+ below and stays there 3 weeks |
| 4 | [04_markdown_effect.sql](../sql/04_markdown_effect.sql) | Sales 4 weeks before vs after each markdown, adjusted for how similar full-price products moved |
| 5 | [05_markdown_candidates.sql](../sql/05_markdown_candidates.sql) | Current full-price lines selling at under half the rate of similar products |
| 6 | [06_weekly_summary.sql](../sql/06_weekly_summary.sql) | Small weekly table for the dashboard trend |

## Key decisions (and why)

- **Kept 3M "duplicate" rows.** The export has no quantity column; buying two of
  an item creates two identical rows. Removing them would have understated sales by 9%.
- **Median, not average, weekly price.** The same product sells at several prices
  in one week (member offers, stores marking down on different days). The median
  ignores a few outliers.
- **Markdown must last 3 weeks.** A 2-week rule was tested first: 44% of the
  shallow "markdowns" it found went back to full price, i.e. they were short
  promotions. With 3 weeks this fell to 21% (≈12% for deeper cuts).
- **Adjusted for the market.** A plain before/after comparison would credit
  markdowns for Black Friday or the start of summer. Each markdown is compared with
  products of the same type still at full price over the same weeks.
- **Peers = same product type *and* department.** Comparing only by type flagged
  65% of Baby/Children as slow, because baby trousers were being judged against
  ladies' trousers.
- **Display fixes at the source.** Rates like 0.3 units/week are converted to units
  sold in 4 weeks, and a trend with no prior sales shows "–" rather than a blank.
- **Clustered, not partitioned.** The BigQuery sandbox deletes date partitions older
  than 60 days, which silently emptied the first 2018–2020 load.

## Full findings

24,901 markdowns were detected. 19,668 of them had enough sales before the markdown
(5+ units in 4 weeks) and a large enough peer group (50+ units) to measure fairly;
the results below use those.

**Markdown depth**

| Depth | Markdowns | Unit lift vs peers | Revenue change vs peers | Grew revenue |
|---|---|---|---|---|
| 15–30% | 3,958 | 1.4× | +7% | 53% |
| **30–50%** | **9,582** | **2.3×** | **+45%** | **67%** |
| 50%+ | 6,128 | 2.6× | +31% | 60% |

**By department**

| Department | Best depth | Revenue change |
|---|---|---|
| Ladieswear | 30–50% | +49% |
| Divided | 30–50% | +55% |
| Baby/Children | 30–50% | +24% |
| Sport | 30–50% | +27% (50%+ **lost** 8%) |
| **Menswear** | **50%+** | +51% |

**Long tail:** 2,122 of 7,541 live full-price lines (28%) sell at under half the
rate of similar products, contributing only 2.6% of units. Their sales fell by
about 50–64% in the last month, faster than the rest of the range.

**Timing:** the share of units sold at markdown peaks in July (~40%) and
December–January (~35%), and is lowest in September (13%).

## Caveats

- **Selection bias:** H&M chose which products to mark down, so they aren't a
  random sample. Adjusting for peers reduces but doesn't remove this.
- **Short window:** effects are measured over 4 weeks after the markdown, not the
  full remaining life of the product.
- **Revenue, not profit:** there's no cost data, so margin impact can't be measured.
  With a typical fashion margin, deep cuts look even less attractive than shown.

## Reproduce

1. Download `articles.csv` and `transactions_train.csv` from Kaggle.
2. `pip install google-cloud-bigquery pydata-google-auth`
3. `python load/load_to_bigquery.py <your-project-id> <folder-with-csvs>`
4. In the BigQuery console, run `sql/01` to `sql/06` in order, replacing
   `data-portfolio-509915` with your project ID.
5. Open `powerbi/HM Markdown.pbip` in Power BI Desktop, point the BigQuery source
   at your project, and refresh. See [powerbi_build_guide.md](powerbi_build_guide.md).
